import Foundation
@main struct FitnessTests {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!
        var points: [DailyMetric] = []
        for offset in 1...35 {
            let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now))!
            points.append(DailyMetric(kind: .restingPulse, date: day, value: offset <= 7 ? 60 : 55, sourceID: "one", sourceName: "One"))
        }
        // Includes the DST boundary; calendar days, not 24-hour arithmetic.
        let trend = FitnessMath.trend(points, now: now, calendar: calendar)
        precondition(trend.recentDays == 7 && trend.baselineDays == 28 && trend.delta == 5)
        precondition(FitnessMath.trend(Array(points.prefix(3)), now: now, calendar: calendar).delta == nil)
        precondition(FitnessMath.mean([]) == nil && FitnessMath.mean([.nan, 12]) == 12)
        let a = Date(timeIntervalSince1970: 1000)
        let duration = FitnessMath.mergedDuration([DateInterval(start: a, duration: 60), DateInterval(start: a.addingTimeInterval(30), duration: 90), DateInterval(start: a.addingTimeInterval(150), duration: 30)])
        precondition(duration == 150) // Overlapping stages never double-count.
        let sleepStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 23))!
        let sleepEnd = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 7))!
        let sleep = FitnessMath.sleepByMorning([DateInterval(start: sleepStart, end: sleepEnd)], calendar: calendar)
        precondition(sleep.count == 1 && sleep.values.first == 9 * 3600)
        let lateMorning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 11, minute: 30))!
        let nap = FitnessMath.sleepByMorning([DateInterval(start: lateMorning, duration: 3600)], calendar: calendar)
        precondition(nap.count == 2 && nap.values.allSatisfy { $0 == 1800 })
        let workout = WorkoutEntry(id: UUID(), date: now, activity: "Run", minutes: 45, effort: 6, note: "", source: "Manual")
        precondition(workout.valid && workout.load == 270)
        var missing = workout; missing.effort = nil
        precondition(missing.load == nil)
        missing.minutes = .infinity; precondition(!missing.valid)
        precondition(FitnessMath.weeklyLoad([workout], now: now, calendar: calendar) == 270)
        let rule = AutomationRule()
        precondition(AutomationEngine.eligible(rule, steps: 10000, goal: 10000, readingDate: now, now: now, receipts: [], calendar: calendar))
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        precondition(!AutomationEngine.eligible(rule, steps: 15000, goal: 10000, readingDate: yesterday, now: now, receipts: [], calendar: calendar))
        let receipt = RuleReceipt(date: now, ruleID: rule.id, day: now, simulated: false, message: "delivered")
        precondition(!AutomationEngine.eligible(rule, steps: 15000, goal: 9000, readingDate: now, now: now, receipts: [receipt], calendar: calendar))
        let recovered = try JSONDecoder().decode([RuleReceipt].self, from: JSONEncoder().encode([receipt]))
        precondition(!AutomationEngine.eligible(rule, steps: 15000, goal: 10000, readingDate: now, now: now, receipts: recovered, calendar: calendar))
        var vibration = rule; vibration.action = .bandVibration
        precondition(vibration.canRun && vibration.vibrationGroups == 1)
        precondition(AutomationEngine.eligible(vibration, steps: 20000, goal: 10000, readingDate: now, now: now, receipts: [], calendar: calendar))
        vibration.trigger = .incomingCall
        precondition(vibration.canRun && !AutomationEngine.eligible(vibration, steps: 20000, goal: 10000, readingDate: now, now: now, receipts: [], calendar: calendar))
        vibration.pattern = "One long pulse"; precondition(!vibration.canRun)
        vibration.pattern = "Three groups"; precondition(vibration.vibrationGroups == 3)
        vibration.trigger = .notification; precondition(!vibration.canRun)
        vibration.trigger = .doubleTap; precondition(!vibration.canRun)
        print("PASS: DST windows, missing data, overlap union, session-RPE load, milestone deduplication and capability gates")
    }
}
