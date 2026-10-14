import Foundation
import UserNotifications
import Combine

final class AutomationDelivery: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
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
    func preview(_ rule: AutomationRule, library: AppStore) {
        let date = Date()
        _ = library.change { $0.receipts.insert(RuleReceipt(date: date, ruleID: rule.id, day: Calendar.current.startOfDay(for: date), simulated: true, message: "Preview only · \(rule.title)"), at: 0) }
        message = "Preview recorded. No band command or shortcut was sent."
    }
}
