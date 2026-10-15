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
        precondition(abs(FitnessMath.standardDeviation([2, 4, 4, 4, 5, 5, 7, 9])! - 2.138) < 0.001)

        // Personal range: constant baseline has zero width; recent 60 sits above it.
        var varied = points
        for offset in 8...40 {
            let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now))!
            varied.removeAll { $0.date == day }
            varied.append(DailyMetric(kind: .restingPulse, date: day, value: offset % 2 == 0 ? 54 : 56, sourceID: "one", sourceName: "One"))
        }
        let signal = FitnessMath.signal(.restingPulse, varied, now: now, calendar: calendar)!
        precondition(signal.position == .above && signal.low < 55 && signal.high > 55)
        precondition(FitnessMath.signal(.restingPulse, Array(varied.prefix(10)), now: now, calendar: calendar) == nil)
        // HRV uses a log scale with ±0.5 SD.
        let hrv = varied.map { DailyMetric(kind: .hrvSDNN, date: $0.date, value: $0.value, sourceID: "one", sourceName: "One") }
        let hrvSignal = FitnessMath.signal(.hrvSDNN, hrv, now: now, calendar: calendar)!
        precondition(hrvSignal.high - hrvSignal.low < signal.high - signal.low)

        let a = Date(timeIntervalSince1970: 1000)
        let duration = FitnessMath.mergedDuration([DateInterval(start: a, duration: 60), DateInterval(start: a.addingTimeInterval(30), duration: 90), DateInterval(start: a.addingTimeInterval(150), duration: 30)])
        precondition(duration == 150) // Overlapping stages never double-count.
        let sleepStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 23))!
        let sleepEnd = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 7))!
        let sleep = FitnessMath.sleepByMorning([DateInterval(start: sleepStart, end: sleepEnd)], calendar: calendar)
        precondition(sleep.count == 1 && sleep.values.first == 9 * 3600) // DST night: 9 real hours.
        let lateMorning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 11, minute: 30))!
        let nap = FitnessMath.sleepByMorning([DateInterval(start: lateMorning, duration: 3600)], calendar: calendar)
        precondition(nap.count == 2 && nap.values.allSatisfy { $0 == 1800 })
        // Midpoint of 23:00 → 07:00 (9 h across the DST change) is 02:30 wall-clock-relative = 3.5 h after midnight in elapsed time.
        let mid = FitnessMath.sleepMidpoints([DateInterval(start: sleepStart, end: sleepEnd)], calendar: calendar)
        precondition(mid.count == 1 && abs(mid.values.first! - 3.5) < 0.001)
        let shortNight = FitnessMath.sleepMidpoints([DateInterval(start: sleepStart, duration: 2 * 3600)], calendar: calendar)
        precondition(shortNight.isEmpty) // No main episode under three hours.

        let workout = WorkoutEntry(id: UUID(), date: now, activity: "Run", minutes: 45, effort: 6, note: "", source: "Manual")
        precondition(workout.valid && workout.load == 270)
        var missing = workout; missing.effort = nil
        precondition(missing.load == nil)
        missing.minutes = .infinity; precondition(!missing.valid)
        precondition(FitnessMath.weeklyLoad([workout], now: now, calendar: calendar) == 270)
        let states = FitnessMath.training([workout], days: 30, now: now, calendar: calendar)
        precondition(states.count == 30 && states.last!.load == 270)
        precondition(abs(states.last!.fatigue - 270 * (1 - exp(-1.0 / 7))) < 0.0001 && states.last!.form < 0)

        precondition(FitnessMath.maximumHeartRate(age: 40) == 180)
        precondition(abs(FitnessMath.cardioFitness(maximum: 180, resting: 60)! - 45.9) < 0.001)
        precondition(FitnessMath.cardioFitness(maximum: 180, resting: 200) == nil)
        let floors = FitnessMath.zoneFloors(maximum: 180, resting: 60)
        precondition(floors == [120, 132, 144, 156, 168])
        precondition(FitnessMath.zone(for: 110, floors: floors) == nil && FitnessMath.zone(for: 150, floors: floors) == 2)
        precondition(FitnessMath.edwardsLoad([10, 10, 0, 0, 2]) == 40)
        precondition(FitnessMath.walkingMinutes(forSteps: 1754) == 18)
        precondition(abs(FitnessMath.rmssd([800, 810, 800, 810, 800, 810, 800, 810, 800, 810, 800])! - 10) < 0.001)

        // Alerts: goal once per day, survives relaunch, milestones collapse.
        var settings = AlertSettings()
        settings.milestone.enabled = true
        var due = AlertEngine.due(settings: settings, goal: 10000, steps: 7600, readAt: now, now: now, delivered: [], calendar: calendar)
        precondition(due.count == 1 && due[0].event == .milestone && due[0].key.hasSuffix("7500") && due[0].settles.count == 3)
        var delivered = Set(due[0].settles)
        precondition(AlertEngine.due(settings: settings, goal: 10000, steps: 7900, readAt: now, now: now, delivered: delivered, calendar: calendar).isEmpty)
        due = AlertEngine.due(settings: settings, goal: 10000, steps: 10100, readAt: now, now: now, delivered: delivered, calendar: calendar)
        precondition(due.count == 1 && due[0].event == .goal)
        delivered.formUnion(due[0].settles)
        let receipts = [AlertReceipt(date: now, event: .goal, key: due[0].key, outcome: "ok")]
        let recovered = try JSONDecoder().decode([AlertReceipt].self, from: JSONEncoder().encode(receipts))
        precondition(AlertEngine.due(settings: settings, goal: 10000, steps: 10200, readAt: now, now: now, delivered: delivered.union(recovered.map(\.key)), calendar: calendar).isEmpty)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        precondition(AlertEngine.due(settings: settings, goal: 10000, steps: 15000, readAt: yesterday, now: now, delivered: [], calendar: calendar).isEmpty)
        // Goal off: a multiple of the milestone equal to the goal still counts as a milestone.
        settings.goal.enabled = false
        due = AlertEngine.due(settings: settings, goal: 10000, steps: 10000, readAt: now, now: now, delivered: [], calendar: calendar)
        precondition(due.count == 1 && due[0].key.hasSuffix("10000"))

        // Move reminder: one sedentary hour inside active hours.
        settings.move.enabled = true
        let samples = [StepSample(date: now.addingTimeInterval(-3600), steps: 4000), StepSample(date: now.addingTimeInterval(-60), steps: 4100)]
        let move = AlertEngine.moveDue(settings: settings, samples: samples, now: now, delivered: [], calendar: calendar)
        precondition(move?.event == .move)
        precondition(AlertEngine.moveDue(settings: settings, samples: samples, now: now, delivered: [move!.key], calendar: calendar) == nil)
        let active = [StepSample(date: now.addingTimeInterval(-3600), steps: 4000), StepSample(date: now.addingTimeInterval(-60), steps: 5200)]
        precondition(AlertEngine.moveDue(settings: settings, samples: active, now: now, delivered: [], calendar: calendar) == nil)
        let night = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now)!
        precondition(AlertEngine.moveDue(settings: settings, samples: samples.map { StepSample(date: $0.date.addingTimeInterval(night.timeIntervalSince(now)), steps: $0.steps) }, now: night, delivered: [], calendar: calendar) == nil)

        // Adaptive checks: sooner when the pace approaches a threshold, never under 5 min.
        settings.goal.enabled = true
        let walking = [StepSample(date: now.addingTimeInterval(-1200), steps: 9000), StepSample(date: now.addingTimeInterval(-60), steps: 9800)]
        let soon = AlertEngine.nextCheck(settings: settings, goal: 10000, samples: walking, now: now, calendar: calendar)
        precondition(soon >= 300 && soon < 600)
        let idle = AlertEngine.nextCheck(settings: settings, goal: 10000, samples: samples, now: now, calendar: calendar)
        precondition(idle == 1800)
        precondition(BuzzPattern.urgent.groups == 4 && BuzzPattern.longGap.beats == [0, 2.8])

        let legacy = try JSONDecoder().decode(AlertSettings.self, from: Data("{\"keepAlive\":true}".utf8))
        precondition(legacy.keepAlive && legacy.goal.enabled && legacy.milestoneStep == 2500)

        // Advanced training load: EWMA ACWR and weekly ramp.
        func session(_ dayOffset: Int, _ load: Int) -> WorkoutEntry {
            WorkoutEntry(id: UUID(), date: calendar.date(byAdding: .day, value: -dayOffset, to: now)!, activity: "Run", minutes: Double(load), effort: 1, note: "", source: "t")
        }
        let steady = (1...40).map { session($0, 50) }
        let balanced = FitnessMath.workloadRatio(steady, now: now, calendar: calendar)
        precondition(balanced.ratio != nil && abs(balanced.ratio! - 1) < 0.15 && balanced.zone == "balanced")
        let spike = FitnessMath.workloadRatio(steady + [session(0, 600), session(0, 600)], now: now, calendar: calendar)
        precondition((spike.ratio ?? 0) > 1.5 && spike.zone == "spike")
        precondition(FitnessMath.workloadRatio([session(1, 50)], now: now, calendar: calendar).ratio == nil)
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let thisWeekDay = calendar.date(byAdding: .hour, value: 1, to: thisWeekStart)!
        let lastWeekDay = calendar.date(byAdding: .day, value: -6, to: thisWeekStart)!
        let ramp = FitnessMath.weeklyRamp([WorkoutEntry(id: UUID(), date: lastWeekDay, activity: "Run", minutes: 100, effort: 1, note: "", source: "t"),
                                           WorkoutEntry(id: UUID(), date: thisWeekDay, activity: "Run", minutes: 200, effort: 1, note: "", source: "t")], now: now, calendar: calendar)
        precondition(ramp == 100)

        // HRV coefficient of variation.
        let flatHRV = (0..<7).map { DailyMetric(kind: .hrvSDNN, date: calendar.date(byAdding: .day, value: -$0, to: now)!, value: 50, sourceID: "s", sourceName: "s") }
        precondition(FitnessMath.coefficientOfVariation([50, 50, 50]) == 0 && FitnessMath.hrvVariation(flatHRV, now: now, calendar: calendar) == 0)

        // Social jetlag: weekend midpoints 2 h later than weekdays.
        var midpoints: [DailyMetric] = []
        for offset in 1...21 {
            let day = calendar.date(byAdding: .day, value: -offset, to: now)!
            midpoints.append(DailyMetric(kind: .sleepMidpoint, date: day, value: calendar.isDateInWeekend(day) ? 5 : 3, sourceID: "s", sourceName: "s"))
        }
        let jetlag = FitnessMath.socialJetlag(midpoints, now: now, calendar: calendar)
        precondition(jetlag != nil && abs(jetlag! - 2) < 0.001)

        // VO2max norms.
        precondition(FitnessMath.cardioCategory(vo2: 55, age: 35, sex: .male)?.label == "Excellent")
        precondition(FitnessMath.cardioCategory(vo2: 20, age: 35, sex: .male)?.label == "Very low")
        precondition(FitnessMath.cardioCategory(vo2: 45, age: 35, sex: .unspecified) == nil)

        // Readiness composite: good HRV + sleep scores high; weights rescale.
        let goodHRV = BodySignal(kind: .hrvSDNN, recent: 60, low: 45, high: 55, recentDays: 7, baselineDays: 60)
        let lowRHR = BodySignal(kind: .restingPulse, recent: 52, low: 54, high: 60, recentDays: 7, baselineDays: 60)
        let ready = FitnessMath.readiness(.init(hrv: goodHRV, rhr: lowRHR, sleepHours: 8, sleepNeed: 8, regularityMinutes: 20))!
        precondition(ready.score > 70 && ready.band == "High" && ready.components.count == 4)
        let poor = FitnessMath.readiness(.init(hrv: BodySignal(kind: .hrvSDNN, recent: 30, low: 45, high: 55, recentDays: 7, baselineDays: 60), rhr: nil, sleepHours: 4, sleepNeed: 8, regularityMinutes: nil))!
        precondition(poor.score < 34 && poor.band == "Low")
        precondition(FitnessMath.readiness(.init(hrv: nil, rhr: nil, sleepHours: 7, sleepNeed: 8, regularityMinutes: 10)) == nil)

        print("PASS: DST windows, personal ranges, sleep timing, training model, heart-rate formulas, alert dedup, ACWR, HRV CV, social jetlag, VO2max norms and readiness")
    }
}
