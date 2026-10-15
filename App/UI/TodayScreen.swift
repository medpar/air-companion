import SwiftUI
import Charts

struct TodayScreen: View {
    @EnvironmentObject private var band: BandConnection
    @EnvironmentObject private var library: AppStore
    @EnvironmentObject private var health: HealthImport
    @State private var editingGoal = false
    @State private var sessionOpen = false
    @State private var logging = false
    @State private var methods = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if !band.keysReady && !library.preview { KeyNeededCard() }
                    StepsCard(editingGoal: $editingGoal)
                    HStack(spacing: 12) { HeartTile(); BatteryTile() }
                    SignalsCard(methods: $methods)
                    TrainingCard(sessionOpen: $sessionOpen, logging: $logging)
                    NextAlarmCard()
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
            }
            .screenBackground()
            .navigationTitle("Today")
            .refreshable { if band.canStart { _ = await band.run { band.start() } } }
            .sheet(isPresented: $editingGoal) { GoalSheet() }
            .sheet(isPresented: $logging) { LogWorkoutSheet() }
            .sheet(isPresented: $methods) { NavigationStack { MethodsScreen() } }
            .fullScreenCover(isPresented: $sessionOpen) { SessionScreen() }
        }
    }

    private var header: some View {
        HStack {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.subheadline).foregroundStyle(Tone.ink2)
            Spacer()
            StatusChip()
        }
        .padding(.top, 2)
    }
}

/// Connection state at a glance. Tap to refresh.
struct StatusChip: View {
    @EnvironmentObject private var band: BandConnection
    @EnvironmentObject private var library: AppStore
    var body: some View {
        Button { if band.canStart { band.start() } } label: {
            HStack(spacing: 6) {
                if band.active { ProgressView().controlSize(.mini) }
                else { Circle().fill(dot).frame(width: 7, height: 7) }
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(Tone.ink).lineLimit(1)
            }
            .padding(.horizontal, 11).frame(height: 28)
            .background(Tone.surface, in: Capsule())
        }
        .buttonStyle(PressStyle())
        .disabled(!band.canStart)
        .animation(.easeOut(duration: 0.2), value: band.active)
        .accessibilityLabel("Band status: \(label)")
        .accessibilityHint(band.canStart ? "Refreshes from your band" : "")
    }
    private var label: String {
        if library.preview { return "Example data" }
        if band.active { return band.status }
        if !band.keysReady { return "Key needed" }
        if band.lastSucceeded == false { return band.status }
        if let read = band.lastRead { return "Synced " + Format.relative(read) }
        return "Not synced"
    }
    private var dot: Color {
        if library.preview { return Tone.moss }
        if band.lastSucceeded == false || !band.keysReady { return Tone.signal }
        return band.lastRead.map { Date().timeIntervalSince($0) < 3600 } == true ? Tone.moss : Tone.ink3
    }
}

private struct StepsCard: View {
    @EnvironmentObject private var band: BandConnection
    @EnvironmentObject private var library: AppStore
    @Binding var editingGoal: Bool
    private var steps: Int? {
        guard let reading = band.activity, Calendar.current.isDateInToday(reading.readAt) else { return nil }
        return reading.steps
    }
    var body: some View {
        let goal = library.data.goal
        let settings = library.data.alerts
        Card {
            HStack {
                Eyebrow("Steps")
                Spacer()
                Button { editingGoal = true } label: {
                    Text("Goal \(goal.formatted())").font(.caption.weight(.semibold)).foregroundStyle(Tone.moss)
                }.buttonStyle(PressStyle())
            }
            Text(steps.map { $0.formatted() } ?? "—")
                .font(.figure(76)).monospacedDigit().foregroundStyle(Tone.ink)
                .contentTransition(.numericText(value: Double(steps ?? 0)))
                .animation(.snappy, value: steps)
                .padding(.top, 6)
            MilestoneTrack(progress: Double(steps ?? 0) / Double(max(goal, 1)),
                           ticks: settings.milestone.enabled ? stride(from: settings.milestoneStep, to: goal, by: max(settings.milestoneStep, 500)).map { Double($0) / Double(goal) } : [])
                .padding(.top, 10)
            HStack {
                Text(caption(goal)).font(.footnote).foregroundStyle(Tone.ink2)
                Spacer()
                if let read = band.activity?.readAt, steps != nil { Text(Format.relative(read)).font(.footnote).foregroundStyle(Tone.ink3) }
            }
            .padding(.top, 12)
        }
        .accessibilityElement(children: .combine)
    }
    private func caption(_ goal: Int) -> String {
        guard let steps else { return band.keysReady ? "Pull down to read your band" : "Connect your band to see steps" }
        let left = goal - steps
        if left <= 0 { return "Goal reached" }
        return "\(left.formatted()) to go · about \(FitnessMath.walkingMinutes(forSteps: left)) min walking"
    }
}

private struct HeartTile: View {
    @EnvironmentObject private var band: BandConnection
    var body: some View {
        let reading = band.activity
        let pulse = reading?.reliableHeartRate == true ? reading?.heartRate : nil
        Card(padding: 16) {
            HStack(spacing: 6) { Image(systemName: "heart.fill").font(.caption).foregroundStyle(Tone.heart); Eyebrow("Heart") }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(pulse.map(String.init) ?? "—").font(.figure(40)).monospacedDigit()
                if pulse != nil { Text("bpm").font(.footnote).foregroundStyle(Tone.ink2) }
            }.padding(.top, 8)
            Text(pulse != nil ? Format.relative(reading!.readAt) : "No steady reading").font(.caption).foregroundStyle(Tone.ink3).padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BatteryTile: View {
    @EnvironmentObject private var band: BandConnection
    var body: some View {
        let percent = band.deviceInfo?.batteryPercent
        Card(padding: 16) {
            HStack(spacing: 6) {
                Image(systemName: symbol(percent)).font(.caption).foregroundStyle((percent ?? 100) < 20 ? Tone.signal : Tone.ink2)
                Eyebrow("Battery")
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(percent.map(String.init) ?? "—").font(.figure(40)).monospacedDigit()
                if percent != nil { Text("%").font(.footnote).foregroundStyle(Tone.ink2) }
            }.padding(.top, 8)
            Text(band.deviceInfo.map { Format.relative($0.readAt) } ?? "Not read yet").font(.caption).foregroundStyle(Tone.ink3).padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }
    private func symbol(_ percent: Int?) -> String {
        guard let percent else { return "battery.50percent" }
        return percent < 20 ? "battery.25percent" : percent < 60 ? "battery.50percent" : percent < 90 ? "battery.75percent" : "battery.100percent"
    }
}

private struct SignalsCard: View {
    @EnvironmentObject private var library: AppStore
    @EnvironmentObject private var health: HealthImport
    @Binding var methods: Bool
    private let kinds: [MetricKind] = [.hrvSDNN, .restingPulse, .sleepHours]
    var body: some View {
        let hasHealth = kinds.contains { !library.points($0).isEmpty }
        Card {
            HStack {
                Eyebrow("Body signals")
                Spacer()
                Button { methods = true } label: { Image(systemName: "info.circle").foregroundStyle(Tone.ink3) }
                    .accessibilityLabel("How body signals work")
            }
            if hasHealth {
                VStack(spacing: 16) {
                    ForEach(kinds) { kind in SignalRow(kind: kind, points: library.points(kind)) }
                }.padding(.top, 14)
                Text("Last 7 days against your previous 60.").font(.caption).foregroundStyle(Tone.ink3).padding(.top, 14)
            } else {
                Text("Sleep, resting heart rate and HRV from Apple Health, compared with your own usual range.")
                    .font(.subheadline).foregroundStyle(Tone.ink2).padding(.top, 10)
                PillButton(title: "Connect Apple Health", symbol: "heart.text.square", prominent: true, busy: health.busy) {
                    health.refresh(into: library)
                }.padding(.top, 14).disabled(library.preview)
            }
        }
    }
}

struct SignalRow: View {
    let kind: MetricKind
    let points: [DailyMetric]
    var body: some View {
        let signal = FitnessMath.signal(kind, points)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.short).font(.subheadline.weight(.medium))
                Spacer()
                if let signal {
                    Text(Format.value(signal.recent, kind)).font(.figure(22)).monospacedDigit()
                    Text(kind.unit).font(.caption).foregroundStyle(Tone.ink2)
                } else {
                    let days = Set(points.map(\.date)).count
                    Text(days == 0 ? "No data" : "Learning · \(min(days, 18))/18 days").font(.caption).foregroundStyle(Tone.ink3)
                }
            }
            if let signal {
                RangeBar(low: signal.low, high: signal.high, value: signal.recent, outside: signal.shown(kind.decimals) != .within)
                Text(describe(signal)).font(.caption).foregroundStyle(signal.shown(kind.decimals) == .within ? Tone.ink2 : Tone.signal)
            }
        }
        .accessibilityElement(children: .combine)
    }
    private func describe(_ signal: BodySignal) -> String {
        let range = "\(Format.value(signal.low, kind))–\(Format.value(signal.high, kind)) \(kind.unit)"
        switch signal.shown(kind.decimals) {
        case .within: return "Within your usual \(range)"
        case .above: return "Above your usual \(range)"
        case .below: return "Below your usual \(range)"
        }
    }
}

private struct TrainingCard: View {
    @EnvironmentObject private var library: AppStore
    @Binding var sessionOpen: Bool
    @Binding var logging: Bool
    var body: some View {
        let states = FitnessMath.training(library.data.workouts, days: 90)
        let recent = Array(states.suffix(42))
        let today = states.last
        let rated = library.data.workouts.contains { $0.load != nil }
        Card {
            Eyebrow("Training")
            if let session = library.data.session {
                Button { sessionOpen = true } label: {
                    HStack {
                        Circle().fill(Tone.moss).frame(width: 8, height: 8)
                        Text((session.activity ?? "Session") + (session.paused ? " · paused" : " · in progress")).font(.subheadline.weight(.medium))
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Duration.seconds(session.elapsed(at: context.date)).formatted(.time(pattern: .hourMinuteSecond))).font(.figure(17)).monospacedDigit()
                        }
                    }
                    .padding(12).background(Tone.mossSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }.buttonStyle(PressStyle()).foregroundStyle(Tone.ink).padding(.top, 12)
            }
            if rated, let today {
                HStack(alignment: .lastTextBaseline, spacing: 18) {
                    figure("Form", today.form, signed: true)
                    figure("Fitness", today.fitness)
                    figure("Fatigue", today.fatigue)
                }.padding(.top, 12)
                Chart(recent) { state in
                    LineMark(x: .value("Day", state.date), y: .value("Load", state.fitness), series: .value("Series", "Fitness"))
                        .foregroundStyle(Tone.moss).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    LineMark(x: .value("Day", state.date), y: .value("Load", state.fatigue), series: .value("Series", "Fatigue"))
                        .foregroundStyle(Tone.ink3).lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3]))
                }
                .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 56).padding(.top, 12)
                .accessibilityLabel("Fitness and fatigue over six weeks")
                Text("Weekly load \(Int(FitnessMath.weeklyLoad(library.data.workouts))) · effort × minutes").font(.caption).foregroundStyle(Tone.ink3).padding(.top, 8)
            } else {
                Text("Log sessions with how hard they felt. Pebble models fitness and fatigue from your load.")
                    .font(.subheadline).foregroundStyle(Tone.ink2).padding(.top, 10)
            }
            HStack(spacing: 10) {
                PillButton(title: library.data.session == nil ? "Start session" : "Open session", symbol: "play.fill", prominent: true) { sessionOpen = true }
                PillButton(title: "Log", symbol: "plus") { logging = true }
            }.padding(.top, 14)
        }
    }
    private func figure(_ label: String, _ value: Double, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(signed ? Format.signed(value) : value.formatted(.number.precision(.fractionLength(0)))).font(.figure(28)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Tone.ink2)
        }
    }
}

private struct NextAlarmCard: View {
    @EnvironmentObject private var band: BandConnection
    var body: some View {
        if let next = band.alarms?.alarms.compactMap({ alarm in nextDate(alarm).map { (alarm, $0) } }).min(by: { $0.1 < $1.1 }) {
            Card {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow("Next alarm")
                        Text(next.0.time).font(.figure(34, .medium)).monospacedDigit()
                        Text(next.0.schedule + (next.0.smartWake ? " · Smart wake" : "")).font(.caption).foregroundStyle(Tone.ink2)
                    }
                    Spacer()
                    Text(next.1, style: .relative).font(.subheadline).foregroundStyle(Tone.ink2).multilineTextAlignment(.trailing)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
    /// Next ring time. Weekday bits run Monday = 0 through Sunday = 6.
    private func nextDate(_ alarm: BandAlarm, now: Date = Date()) -> Date? {
        guard alarm.enabled else { return nil }
        let calendar = Calendar.current
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let time = calendar.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: day), time > now else { continue }
            if !alarm.recurring { return time }
            let bit = (calendar.component(.weekday, from: day) + 5) % 7
            if alarm.days & UInt8(1 << bit) != 0 { return time }
        }
        return nil
    }
}

struct KeyNeededCard: View {
    var body: some View {
        Card {
            HStack(spacing: 14) {
                PebbleMark(size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect your Air").font(.headline)
                    Text("Import your device key in the Band tab.").font(.subheadline).foregroundStyle(Tone.ink2)
                }
            }
        }
    }
}

struct GoalSheet: View {
    @EnvironmentObject private var library: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(library.data.goal.formatted()).font(.figure(64)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(library.data.goal))).animation(.snappy, value: library.data.goal)
                Stepper("Daily goal", value: Binding(get: { library.data.goal }, set: { value in library.change { $0.goal = value } }), in: 2000...40000, step: 500)
                    .labelsHidden()
                Text("Daily steps linked to lower mortality level off around 8,000–10,000 for adults under 60 and 6,000–8,000 for those 60 and over (Paluch et al., 2022).")
                    .font(.footnote).foregroundStyle(Tone.ink2).multilineTextAlignment(.center)
            }
            .padding(24).frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("Daily goal").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.height(340)])
    }
}
