import Foundation

enum MetricKind: String, Codable, CaseIterable, Identifiable {
    case restingPulse, hrvSDNN, sleepHours, steps
    var id: String { rawValue }
    var title: String { switch self { case .restingPulse: return "Resting heart rate"; case .hrvSDNN: return "Heart rate variability"; case .sleepHours: return "Sleep duration"; case .steps: return "Steps" } }
    var unit: String { switch self { case .restingPulse: return "bpm"; case .hrvSDNN: return "ms SDNN"; case .sleepHours: return "hours"; case .steps: return "steps" } }
    var symbol: String { switch self { case .restingPulse: return "heart"; case .hrvSDNN: return "waveform.path.ecg"; case .sleepHours: return "bed.double"; case .steps: return "figure.walk" } }
}
struct DailyMetric: Codable, Identifiable {
    var id: String { "\(kind.rawValue)-\(sourceID)-\(date.timeIntervalSince1970)" }
    let kind: MetricKind
    let date: Date
    let value: Double
    let sourceID: String
    let sourceName: String
}
struct WorkoutEntry: Codable, Identifiable {
    let id: UUID
    var date: Date
    var activity: String
    var minutes: Double
    var effort: Int?
    var note: String
    var source: String
    var load: Double? { effort.map { minutes * Double($0) } }
    var valid: Bool { minutes.isFinite && minutes > 0 && minutes <= 1440 && (effort == nil || (0...10).contains(effort!)) && note.count <= 2000 }
}
struct MetricTrend {
    let recent: Double?
    let baseline: Double?
    let recentDays: Int
    let baselineDays: Int
    var delta: Double? { guard recentDays >= 4, baselineDays >= 14, let recent, let baseline else { return nil }; return recent - baseline }
}
enum FitnessMath {
    static func mean(_ values: [Double]) -> Double? {
        let values = values.filter(\.isFinite)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
    /// Seven completed local days versus the preceding 28. Missing days are not zero.
    static func trend(_ values: [DailyMetric], now: Date = Date(), calendar: Calendar = .current) -> MetricTrend {
        let today = calendar.startOfDay(for: now)
        let recentStart = calendar.date(byAdding: .day, value: -7, to: today)!
        let baselineStart = calendar.date(byAdding: .day, value: -35, to: today)!
        let recent = values.filter { $0.date >= recentStart && $0.date < today }
        let baseline = values.filter { $0.date >= baselineStart && $0.date < recentStart }
        return MetricTrend(recent: mean(recent.map(\.value)), baseline: mean(baseline.map(\.value)), recentDays: Set(recent.map { calendar.startOfDay(for: $0.date) }).count, baselineDays: Set(baseline.map { calendar.startOfDay(for: $0.date) }).count)
    }
    static func mergedDuration(_ intervals: [DateInterval]) -> TimeInterval {
        let ordered = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard var current = ordered.first else { return 0 }
        var total: TimeInterval = 0
        for interval in ordered.dropFirst() {
            if interval.start <= current.end { current = DateInterval(start: current.start, end: max(current.end, interval.end)) }
            else { total += current.duration; current = interval }
        }
        return total + current.duration
    }
    static func sleepByMorning(_ intervals: [DateInterval], calendar: Calendar = .current) -> [Date: TimeInterval] {
        var bins: [Date: [DateInterval]] = [:]
        for interval in intervals where interval.duration > 0 {
            var cursor = interval.start
            while cursor < interval.end {
                let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: cursor)!
                let start = cursor < noon ? calendar.date(byAdding: .day, value: -1, to: noon)! : noon
                let boundary = calendar.date(byAdding: .day, value: 1, to: start)!
                let end = min(boundary, interval.end)
                guard end > cursor else { break }
                bins[calendar.startOfDay(for: boundary), default: []].append(DateInterval(start: cursor, end: end))
                cursor = end
            }
        }
        return bins.mapValues(mergedDuration)
    }
    static func weeklyLoad(_ workouts: [WorkoutEntry], now: Date = Date(), calendar: Calendar = .current) -> Double {
        let start = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        return workouts.filter { $0.date >= start && $0.date <= now }.compactMap(\.load).reduce(0, +)
    }
}

enum RuleTrigger: String, Codable, CaseIterable, Identifiable {
    case stepGoal, incomingCall, notification, doubleTap
    var id: String { rawValue }
    var title: String { switch self { case .stepGoal: return "Daily step goal"; case .incomingCall: return "Incoming call"; case .notification: return "App notification"; case .doubleTap: return "Double tap" } }
}
enum RuleAction: String, Codable, CaseIterable, Identifiable {
    case phoneAlert, bandVibration, bandLight, shortcut
    var id: String { rawValue }
    var title: String { switch self { case .phoneAlert: return "iPhone notification"; case .bandVibration: return "Band vibration"; case .bandLight: return "Band light"; case .shortcut: return "Run a shortcut" } }
    var available: Bool { self == .phoneAlert || self == .bandVibration }
}
struct AutomationRule: Codable, Identifiable {
    var id = UUID()
    var trigger = RuleTrigger.stepGoal
    var action = RuleAction.phoneAlert
    var enabled = true
    var pattern = "Short vibration"
    var light = "White"
    var shortcut = ""
    var title: String { "\(trigger.title) → \(action.title)" }
    var vibrationGroups: Int? { ["Short vibration": 1, "Two groups": 2, "Three groups": 3][pattern] }
    var canRun: Bool {
        (trigger == .stepGoal && action == .phoneAlert) ||
        ((trigger == .stepGoal || trigger == .incomingCall) && action == .bandVibration && vibrationGroups != nil)
    }
    var executionNote: String {
        guard canRun else { return "Draft only. This combination needs a supported iOS route or an identified Air command." }
        if trigger == .incomingCall { return "Refresh once after opening Air Companion. Incoming calls can then vibrate while the app stays open. Locked/background delivery is not supported; busy or unavailable bands are skipped." }
        return action == .bandVibration ? "Vibrates once per day after a refresh reaches your goal. Each group switches intensity and restores it. Requires an available Air with vibration on; steps are not monitored continuously." : "Notifies this iPhone once per day after a refresh reaches your goal. Steps are not monitored continuously."
    }
}
struct RuleReceipt: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let ruleID: UUID
    let day: Date
    let simulated: Bool
    var message: String
    var sourceEventID: String? = nil
}
enum AutomationEngine {
    /// Consumes a current-day snapshot. One delivery per rule per local day,
    /// including after relaunch, repeated refreshes, or a same-day goal change.
    static func eligible(_ rule: AutomationRule, steps: Int, goal: Int, readingDate: Date, now: Date,
                         receipts: [RuleReceipt], calendar: Calendar = .current) -> Bool {
        guard rule.enabled, rule.canRun, rule.trigger == .stepGoal, goal > 0, steps >= goal,
              calendar.isDate(readingDate, inSameDayAs: now) else { return false }
        return !receipts.contains { $0.ruleID == rule.id && !$0.simulated && calendar.isDate($0.day, inSameDayAs: now) }
    }
}

struct WorkoutSession: Codable {
    let startedAt: Date
    var resumedAt: Date?
    var accumulated: TimeInterval
    init(now: Date = Date()) { startedAt = now; resumedAt = now; accumulated = 0 }
    func elapsed(at now: Date) -> TimeInterval { accumulated + (resumedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0) }
    mutating func pause(at now: Date) { accumulated = elapsed(at: now); resumedAt = nil }
    mutating func resume(at now: Date) { if resumedAt == nil { resumedAt = now } }
}
