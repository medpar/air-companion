import Foundation
import UserNotifications
import Combine
import CallKit
import UIKit

final class AutomationDelivery: NSObject, ObservableObject, UNUserNotificationCenterDelegate, CXCallObserverDelegate {
    private let calls = CXCallObserver()
    private weak var library: AppStore?
    private weak var band: BandConnection?
    @Published private(set) var testingNotification = false
    private var testIdentifier: String?
    private var testDelivered = false
    private var testGroups = 3
    private var testTimeout: Timer?
    private var testEvents: [[String: String]] = []
    func bind(library: AppStore, band: BandConnection) {
        guard self.library !== library else { return }
        self.library = library; self.band = band
        calls.setDelegate(self, queue: .main)
    }
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        guard !call.isOutgoing, !call.hasConnected, !call.hasEnded,
              band?.observingEvents != true,
              UIApplication.shared.applicationState != .background,
              let library, !library.preview else { return }
        for rule in library.data.rules where rule.enabled && rule.canRun && rule.trigger == .incomingCall {
            guard !library.data.receipts.contains(where: { $0.ruleID == rule.id && $0.sourceEventID == call.uuid.uuidString }) else { continue }
            deliverBand(rule, library: library, eventID: call.uuid.uuidString)
        }
    }
    override init() { super.init(); UNUserNotificationCenter.current().delegate = self }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
        let identifier = notification.request.identifier
        DispatchQueue.main.async { [weak self] in
            guard let self, self.testIdentifier == identifier, !self.testDelivered else { return }
            self.testDelivered = true
            self.recordTest("notification_received")
            guard let band = self.band, UIApplication.shared.applicationState != .background else {
                self.finishTest("Test stopped: keep Air Companion open."); return
            }
            let groups = self.testGroups
            band.testVibration(groups: groups) { [weak self] success in
                guard let self, self.testIdentifier == identifier else { return }
                self.finishTest(success ? "\(groups) vibration groups complete · original intensity restored" : "Test vibration incomplete · check My Air")
            }
        }
    }
    func sendTestNotification(groups: Int = 3) {
        guard !testingNotification, let band, band.canStart, !band.observingEvents,
              library?.preview == false, (1...3).contains(groups) else {
            message = "Keep Air Companion open with your Air nearby, then try again."; return
        }
        let identifier = "air-test-\(UUID().uuidString)"
        testIdentifier = identifier; testDelivered = false; testGroups = groups; testEvents = []
        testingNotification = true; message = "Preparing test notification…"
        recordTest("test_started", value: String(groups))
        testTimeout = Timer(timeInterval: 60, repeats: false) { [weak self] _ in
            self?.finishTest("Test timed out. Check notification permission and keep the app open.")
        }
        if let testTimeout { RunLoop.main.add(testTimeout, forMode: .common) }
        Task { @MainActor in
            do {
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                guard testIdentifier == identifier else { return }
                recordTest("authorization", value: String(settings.authorizationStatus.rawValue))
                let authorized = try await center.requestAuthorization(options: [.alert, .sound])
                guard testIdentifier == identifier else { return }
                guard authorized else {
                    finishTest("Allow notifications for Air Companion in iPhone Settings."); return
                }
                guard testIdentifier == identifier, UIApplication.shared.applicationState != .background else { return }
                band.prepareVibration { [weak self] ready in
                    guard let self, self.testIdentifier == identifier else { return }
                    guard ready else { self.finishTest("Band could not prepare the test. Check My Air."); return }
                    self.recordTest("band_ready")
                    Task { @MainActor in
                        let content = UNMutableNotificationContent()
                        content.title = "Air Companion test"
                        content.body = "Your Air will vibrate in \(groups) short groups."
                        content.sound = .default
                        do {
                            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)))
                            guard self.testIdentifier == identifier else { center.removePendingNotificationRequests(withIdentifiers: [identifier]); return }
                            self.recordTest("notification_scheduled")
                            self.message = "Test notification arrives in two seconds."
                        } catch {
                            if self.testIdentifier == identifier { self.finishTest("Couldn’t schedule the test notification.") }
                        }
                    }
                }
            } catch { if testIdentifier == identifier { finishTest("Couldn’t request notification permission.") } }
        }
    }
    func cancelNotificationTest() {
        guard testingNotification else { return }
        finishTest("Test stopped when Air Companion left the foreground.")
    }
    private func finishTest(_ result: String) {
        guard testingNotification else { return }
        if let testIdentifier { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [testIdentifier]) }
        testIdentifier = nil; testingNotification = false
        testTimeout?.invalidate(); testTimeout = nil
        recordTest("ended", value: result); message = result
        band?.stop()
    }
    private func recordTest(_ event: String, value: String = "") {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        testEvents.append(["event": event, "value": value, "time": formatter.string(from: Date())])
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("notification-test-report.json")
        if let data = try? JSONSerialization.data(withJSONObject: testEvents, options: .prettyPrinted) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
    @Published var message: String?
    private var delivering: Set<UUID> = []
    func evaluate(library: AppStore, reading: ActivityReading) {
        guard !library.preview, band?.observingEvents != true, let steps = reading.steps else { return }
        let now = Date()
        for rule in library.data.rules where AutomationEngine.eligible(rule, steps: steps, goal: library.data.goal, readingDate: reading.readAt, now: now, receipts: library.data.receipts) && !delivering.contains(rule.id) {
            if rule.action == .bandVibration {
                deliverBand(rule, library: library, eventID: nil, reading: reading)
                continue
            }
            delivering.insert(rule.id)
            Task { @MainActor in
                defer { delivering.remove(rule.id) }
                do {
                    let center = UNUserNotificationCenter.current()
                    guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                        message = "Allow notifications in Settings to receive your step-goal alert."; return
                    }
                    guard !library.preview, band?.observingEvents != true, library.data.rules.contains(where: { $0.id == rule.id && $0.enabled && $0.canRun }) else { return }
                    // Journal before scheduling, favoring no duplicate alerts if the process exits.
                    let receipt = RuleReceipt(date: now, ruleID: rule.id, day: Calendar.current.startOfDay(for: now), simulated: false, message: "Step-goal notification scheduled on iPhone")
                    guard library.change({ $0.receipts.append(receipt) }) else { return }
                    let content = UNMutableNotificationContent()
                    content.title = "Daily goal reached"
                    content.body = "You’ve reached your \(library.data.goal.formatted())-step goal."
                    content.sound = .default
                    do {
                        try await center.add(UNNotificationRequest(identifier: "air-goal-\(rule.id)-\(receipt.day.timeIntervalSince1970)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
                        message = "Your step-goal notification is scheduled."
                    } catch {
                        _ = library.change { $0.receipts.removeAll { $0.id == receipt.id } }
                        throw error
                    }
                } catch { message = "The step-goal notification could not be scheduled." }
            }
        }
    }
    private func deliverBand(_ rule: AutomationRule, library: AppStore, eventID: String?, reading: ActivityReading? = nil) {
        guard !delivering.contains(rule.id), let band, let groups = rule.vibrationGroups else { return }
        delivering.insert(rule.id)
        Task { @MainActor [weak self, weak library, weak band] in
            guard let self, let library, let band else { return }
            defer { self.delivering.remove(rule.id) }
            // The refresh ends before CoreBluetooth confirms disconnection.
            // Wait briefly for that callback; never compete with another task.
            for _ in 0..<20 where !band.canStart {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard !library.preview, !band.observingEvents, UIApplication.shared.applicationState != .background,
                  library.data.rules.contains(where: { $0.id == rule.id && $0.enabled && $0.canRun && $0.trigger == rule.trigger && $0.action == rule.action && $0.pattern == rule.pattern }), band.canPulse else {
                self.message = "Band alert skipped: the Air is busy, unavailable, or vibration is off."; return
            }
            if let eventID {
                guard self.calls.calls.contains(where: { $0.uuid.uuidString == eventID && !$0.isOutgoing && !$0.hasConnected && !$0.hasEnded }) else { return }
            }
            let now = Date()
            if let reading {
                guard let steps = reading.steps, AutomationEngine.eligible(rule, steps: steps, goal: library.data.goal, readingDate: reading.readAt, now: now, receipts: library.data.receipts) else { return }
            }
            var receipt = RuleReceipt(date: now, ruleID: rule.id, day: Calendar.current.startOfDay(for: now), simulated: false, message: "Band vibration requested")
            receipt.sourceEventID = eventID
            // Persist before starting: an interrupted attempt must not replay
            // the pulse on the next refresh or repeated call-state callback.
            guard library.change({ $0.receipts.append(receipt) }) else { return }
            band.testVibration(groups: groups) { [weak self, weak library] success in
                let message = success ? "Band vibration completed · original intensity restored" : "Band vibration incomplete · review My Air before retrying"
                self?.message = message
                _ = library?.change { data in
                    if let index = data.receipts.firstIndex(where: { $0.id == receipt.id }) { data.receipts[index].message = message }
                }
            }
        }
    }
    func preview(_ rule: AutomationRule, library: AppStore) {
        let date = Date()
        _ = library.change { $0.receipts.insert(RuleReceipt(date: date, ruleID: rule.id, day: Calendar.current.startOfDay(for: date), simulated: true, message: "Preview only · \(rule.title)"), at: 0) }
        message = "Preview recorded. No band command or shortcut was sent."
    }
}
