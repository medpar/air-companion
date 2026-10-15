import Foundation
import UserNotifications
import Combine
import CallKit
import UIKit

final class AutomationDelivery: NSObject, ObservableObject, UNUserNotificationCenterDelegate, CXCallObserverDelegate {
    private let calls = CXCallObserver()
    private weak var library: AppStore?
    private weak var band: BandConnection?
    func bind(library: AppStore, band: BandConnection) {
        guard self.library !== library else { return }
        self.library = library; self.band = band
        calls.setDelegate(self, queue: .main)
    }
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        guard !call.isOutgoing, !call.hasConnected, !call.hasEnded,
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
    }
    @Published var message: String?
    private var delivering: Set<UUID> = []
    func evaluate(library: AppStore, reading: ActivityReading) {
        guard !library.preview, let steps = reading.steps else { return }
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
                    guard !library.preview, library.data.rules.contains(where: { $0.id == rule.id && $0.enabled && $0.canRun }) else { return }
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
            guard !library.preview, UIApplication.shared.applicationState != .background,
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
