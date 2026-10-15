import Foundation

/// A pattern is a sequence of verified intensity-feedback groups separated by
/// gaps. Timing is approximate: each group waits for band acknowledgements.
enum BuzzPattern: String, Codable, CaseIterable, Identifiable {
    case single, double, triple, longGap, urgent
    var id: String { rawValue }
    var gaps: [TimeInterval] {
        switch self {
        case .single: return []
        case .double: return [0.8]
        case .triple: return [0.8, 0.8]
        case .longGap: return [1.8]
        case .urgent: return [0.45, 1.35, 0.45]
        }
    }
    var groups: Int { gaps.count + 1 }
    var title: String {
        switch self {
        case .single: return "Single"
        case .double: return "Double"
        case .triple: return "Triple"
        case .longGap: return "Long gap"
        case .urgent: return "Urgent"
        }
    }
    /// Relative beat positions for drawing the pattern (0 = first group).
    var beats: [TimeInterval] { gaps.reduce(into: [0]) { $0.append($0.last! + 1 + $1) } }
}

enum AlertEvent: String, Codable, CaseIterable, Identifiable {
    case call, goal, milestone, move, shortcut
    var id: String { rawValue }
    var title: String {
        switch self {
        case .call: return "Incoming calls"
        case .goal: return "Daily goal"
        case .milestone: return "Step milestones"
        case .move: return "Move reminder"
        case .shortcut: return "Shortcuts"
        }
    }
    var symbol: String {
        switch self {
        case .call: return "phone"
        case .goal: return "flag.checkered"
        case .milestone: return "figure.walk"
        case .move: return "chair"
        case .shortcut: return "square.2.layers.3d"
        }
    }
}

struct AlertRule: Codable, Equatable {
    var enabled: Bool
    var pattern: BuzzPattern
    var notifyPhone = false
    var webhook = false
}

struct AlertSettings: Codable, Equatable {
    var call = AlertRule(enabled: false, pattern: .urgent)
    var goal = AlertRule(enabled: true, pattern: .triple, notifyPhone: true)
    var milestone = AlertRule(enabled: false, pattern: .single)
    var milestoneStep = 2500
    var move = AlertRule(enabled: false, pattern: .double)
    /// Fewer steps than this within the past hour counts as a sedentary hour.
    var moveThreshold = 250
    var activeStart = 9
    var activeEnd = 21
    var shortcutPattern = BuzzPattern.double
    var keepAlive = false
    var webhookURL = ""

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertSettings()
        call = try c.decodeIfPresent(AlertRule.self, forKey: .call) ?? d.call
        goal = try c.decodeIfPresent(AlertRule.self, forKey: .goal) ?? d.goal
        milestone = try c.decodeIfPresent(AlertRule.self, forKey: .milestone) ?? d.milestone
        milestoneStep = try c.decodeIfPresent(Int.self, forKey: .milestoneStep) ?? d.milestoneStep
        move = try c.decodeIfPresent(AlertRule.self, forKey: .move) ?? d.move
        moveThreshold = try c.decodeIfPresent(Int.self, forKey: .moveThreshold) ?? d.moveThreshold
        activeStart = try c.decodeIfPresent(Int.self, forKey: .activeStart) ?? d.activeStart
        activeEnd = try c.decodeIfPresent(Int.self, forKey: .activeEnd) ?? d.activeEnd
        shortcutPattern = try c.decodeIfPresent(BuzzPattern.self, forKey: .shortcutPattern) ?? d.shortcutPattern
        keepAlive = try c.decodeIfPresent(Bool.self, forKey: .keepAlive) ?? d.keepAlive
        webhookURL = try c.decodeIfPresent(String.self, forKey: .webhookURL) ?? d.webhookURL
    }
    func rule(_ event: AlertEvent) -> AlertRule {
        switch event {
        case .call: return call
        case .goal: return goal
        case .milestone: return milestone
        case .move: return move
        case .shortcut: return AlertRule(enabled: true, pattern: shortcutPattern)
        }
    }
    mutating func set(_ event: AlertEvent, _ rule: AlertRule) {
        switch event {
        case .call: call = rule
        case .goal: goal = rule
        case .milestone: milestone = rule
        case .move: move = rule
        case .shortcut: shortcutPattern = rule.pattern
        }
    }
    var needsStepChecks: Bool { goal.enabled || milestone.enabled || move.enabled }
}

/// Persisted before delivery so a relaunch or repeated refresh never replays it.
struct AlertReceipt: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let event: AlertEvent
    let key: String
    var outcome: String
}

struct StepSample: Codable, Equatable {
    let date: Date
    let steps: Int
}

struct DueAlert: Equatable {
    let event: AlertEvent
    let key: String
    /// Every key this delivery settles (lower milestones crossed at once).
    let settles: [String]
}

enum AlertEngine {
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Goal and milestone alerts for a same-day reading. Several milestones
    /// crossed between checks produce one delivery for the highest one.
    static func due(settings: AlertSettings, goal: Int, steps: Int, readAt: Date, now: Date,
                    delivered: Set<String>, calendar: Calendar = .current) -> [DueAlert] {
        guard calendar.isDate(readAt, inSameDayAs: now) else { return [] }
        let day = dayKey(now, calendar: calendar)
        var result: [DueAlert] = []
        if settings.goal.enabled, goal > 0, steps >= goal {
            let key = "goal-\(day)"
            if !delivered.contains(key) { result.append(DueAlert(event: .goal, key: key, settles: [key])) }
        }
        let step = settings.milestoneStep
        if settings.milestone.enabled, step >= 500 {
            let crossed = (1...max(1, steps / step)).map { $0 * step }.filter { $0 <= steps && !(settings.goal.enabled && $0 == goal) }
            let open = crossed.map { "milestone-\(day)-\($0)" }.filter { !delivered.contains($0) }
            // The goal alert already marks the moment; don't stack a milestone on it.
            if let last = open.last, !result.contains(where: { $0.event == .goal }) {
                result.append(DueAlert(event: .milestone, key: last, settles: open))
            } else if !open.isEmpty, result.contains(where: { $0.event == .goal }) {
                result[0] = DueAlert(event: .goal, key: result[0].key, settles: result[0].settles + open)
            }
        }
        return result
    }

    /// A sedentary hour inside active hours, judged from two band snapshots at
    /// least 55 minutes apart. At most one reminder per clock hour.
    static func moveDue(settings: AlertSettings, samples: [StepSample], now: Date,
                        delivered: Set<String>, calendar: Calendar = .current) -> DueAlert? {
        guard settings.move.enabled else { return nil }
        let hour = calendar.component(.hour, from: now)
        guard hour >= settings.activeStart, hour < settings.activeEnd,
              let latest = samples.last, now.timeIntervalSince(latest.date) < 15 * 60,
              let earlier = samples.last(where: { latest.date.timeIntervalSince($0.date) >= 55 * 60 }),
              latest.date.timeIntervalSince(earlier.date) <= 90 * 60,
              calendar.isDate(earlier.date, inSameDayAs: latest.date),
              latest.steps - earlier.steps < settings.moveThreshold else { return nil }
        let key = "move-\(dayKey(now, calendar: calendar))-\(hour)"
        let previousHour = "move-\(dayKey(now, calendar: calendar))-\(hour - 1)"
        guard !delivered.contains(key), !delivered.contains(previousHour) else { return nil }
        return DueAlert(event: .move, key: key, settles: [key])
    }

    /// Recent pace in steps per minute from same-day snapshots within two hours.
    static func pace(_ samples: [StepSample], calendar: Calendar = .current) -> Double? {
        guard let latest = samples.last,
              let earlier = samples.last(where: { latest.date.timeIntervalSince($0.date) >= 10 * 60 && latest.date.timeIntervalSince($0.date) <= 2 * 3600 }),
              calendar.isDate(earlier.date, inSameDayAs: latest.date), latest.steps >= earlier.steps else { return nil }
        return Double(latest.steps - earlier.steps) / (latest.date.timeIntervalSince(earlier.date) / 60)
    }

    /// Seconds until the next band check. Checks arrive sooner when the current
    /// pace approaches the next threshold, and stay sparse otherwise, so the band
    /// is shared with Google Health as little as possible.
    static func nextCheck(settings: AlertSettings, goal: Int, samples: [StepSample], now: Date,
                          calendar: Calendar = .current) -> TimeInterval {
        let minimum: TimeInterval = 5 * 60, relaxed: TimeInterval = 30 * 60
        let hour = calendar.component(.hour, from: now)
        guard settings.needsStepChecks else { return 60 * 60 }
        if hour < 6 { return 60 * 60 }
        guard let latest = samples.last, calendar.isDate(latest.date, inSameDayAs: now) else { return minimum }
        var targets: [Int] = []
        if settings.goal.enabled, latest.steps < goal { targets.append(goal) }
        if settings.milestone.enabled, settings.milestoneStep >= 500 {
            targets.append((latest.steps / settings.milestoneStep + 1) * settings.milestoneStep)
        }
        var delay = settings.move.enabled && hour >= settings.activeStart && hour < settings.activeEnd ? relaxed : 45 * 60
        if let target = targets.min(), let pace = pace(samples), pace > 2 {
            let eta = Double(target - latest.steps) / pace * 60
            delay = min(delay, max(minimum, eta * 0.9))
        }
        return delay
    }
}
