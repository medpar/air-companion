import SwiftUI
import Charts

private enum TrendTopic: Hashable, CaseIterable, Identifiable {
    case metric(MetricKind), training
    static var allCases: [TrendTopic] { [.metric(.steps), .metric(.sleepHours), .metric(.restingPulse), .metric(.hrvSDNN), .metric(.sleepMidpoint), .training] }
    var id: String { title }
    var title: String { if case .metric(let kind) = self { return kind.short }; return "Training" }
}

struct TrendsScreen: View {
    @EnvironmentObject private var library: AppStore
    @State private var topic = TrendTopic.metric(.steps)
    @State private var weeks = 4
    @State private var methods = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TopicBar(topic: $topic)
                    switch topic {
                    case .metric(let kind): MetricTrendView(kind: kind, weeks: $weeks)
                    case .training: TrainingTrendView()
                    }
                    Button { methods = true } label: {
                        Label("How these are calculated", systemImage: "book.closed").font(.footnote.weight(.medium)).foregroundStyle(Tone.ink2)
                    }.buttonStyle(PressStyle()).padding(.horizontal, 4).padding(.top, 4)
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
            }
            .screenBackground()
            .navigationTitle("Trends")
            .sheet(isPresented: $methods) { NavigationStack { MethodsScreen() } }
        }
    }
}

private struct TopicBar: View {
    @Binding var topic: TrendTopic
    @Namespace private var selection
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TrendTopic.allCases) { item in
                    Button { withAnimation(.snappy(duration: 0.25)) { topic = item } } label: {
                        Text(item.title).font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).frame(height: 34)
                            .foregroundStyle(topic == item ? Tone.onMoss : Tone.ink)
                            .background {
                                if topic == item { Capsule().fill(Tone.moss).matchedGeometryEffect(id: "chip", in: selection) }
                                else { Capsule().fill(Tone.surface) }
                            }
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(topic == item ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: topic)
    }
}

private struct MetricTrendView: View {
    @EnvironmentObject private var library: AppStore
    let kind: MetricKind
    @Binding var weeks: Int
    var body: some View {
        let points = library.points(kind)
        let start = Calendar.current.date(byAdding: .day, value: -weeks * 7, to: Calendar.current.startOfDay(for: Date()))!
        let visible = points.filter { $0.date >= start }
        let trend = FitnessMath.trend(points)
        let signal = kind == .sleepMidpoint ? nil : FitnessMath.signal(kind, points)
        Card {
            Eyebrow(kind.title)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(trend.recent.map { Format.value($0, kind) } ?? "—").font(.figure(56)).monospacedDigit()
                Text(kind == .sleepMidpoint ? "avg midpoint" : kind.unit).font(.subheadline).foregroundStyle(Tone.ink2)
                Spacer()
                if let delta = trend.delta, kind != .sleepMidpoint { DeltaChip(delta: delta, kind: kind) }
            }.padding(.top, 6)
            Text("7-day average · \(trend.recentDays) of 7 days").font(.caption).foregroundStyle(Tone.ink3)
            if visible.isEmpty {
                Text(emptyMessage).font(.subheadline).foregroundStyle(Tone.ink2).frame(maxWidth: .infinity, minHeight: 160)
            } else {
                MetricChart(kind: kind, points: visible, signal: signal).frame(height: 190).padding(.top, 16)
            }
            Picker("Range", selection: $weeks) { Text("4 weeks").tag(4); Text("12 weeks").tag(12) }
                .pickerStyle(.segmented).padding(.top, 14)
        }
        if kind == .sleepMidpoint, let sd = FitnessMath.regularity(points) {
            Card {
                Eyebrow("Regularity")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("±\(Int(sd.rounded()))").font(.figure(40)).monospacedDigit()
                    Text("min night to night").font(.subheadline).foregroundStyle(Tone.ink2)
                }.padding(.top, 6)
                Text("Variation of your sleep midpoint over two weeks. Steadier timing supports your body clock.").font(.footnote).foregroundStyle(Tone.ink2).padding(.top, 6)
                if let jetlag = FitnessMath.socialJetlag(points) {
                    Divider().padding(.vertical, 12)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Format.clock(hours: jetlag)).font(.figure(28)).monospacedDigit()
                        Text("social jetlag").font(.subheadline).foregroundStyle(Tone.ink2)
                    }
                    Text("Gap between your weekend and weekday sleep midpoints (Wittmann et al., 2006). Smaller is gentler on your body clock.").font(.caption).foregroundStyle(Tone.ink3).padding(.top, 6)
                }
            }
        }
        if let signal {
            Card {
                Eyebrow("Your usual range")
                RangeBar(low: signal.low, high: signal.high, value: signal.recent, outside: signal.shown(kind.decimals) != .within).padding(.top, 14)
                HStack {
                    Text("\(Format.value(signal.low, kind))–\(Format.value(signal.high, kind)) \(kind.unit)").font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(signal.baselineDays) days of history").font(.caption).foregroundStyle(Tone.ink3)
                }.padding(.top, 10)
                Text(note).font(.footnote).foregroundStyle(Tone.ink2).padding(.top, 8)
            }
        }
        SourceCard(kind: kind)
    }
    private var emptyMessage: String {
        kind == .steps ? "Daily steps appear as you sync your band or import Apple Health." : "Import Apple Health in the Band tab to see this trend."
    }
    private var note: String {
        switch kind {
        case .hrvSDNN: return "HRV is compared on a log scale with a ±0.5 SD band, the smallest change considered meaningful in daily HRV monitoring. Apple Health stores SDNN, so values aren’t comparable with RMSSD-based apps."
        case .restingPulse: return "A resting heart rate above your usual range for several days often follows hard training, poor sleep, alcohol or illness."
        case .sleepHours: return "Adults are advised to sleep at least 7 hours regularly (AASM/SRS consensus)."
        case .steps: return "More daily steps are linked to lower mortality, with benefits levelling off around 8,000–10,000 steps."
        case .sleepMidpoint: return ""
        }
    }
}

private struct DeltaChip: View {
    let delta: Double
    let kind: MetricKind
    var body: some View {
        let favourable = kind.higherIsBetter.map { $0 == (delta >= 0) } ?? true
        let text = (delta >= 0 ? "+" : "−") + Format.value(abs(delta), kind)
        Text(text).font(.caption.weight(.semibold)).monospacedDigit()
            .padding(.horizontal, 8).frame(height: 24)
            .foregroundStyle(favourable ? Tone.moss : Tone.signal)
            .background(favourable ? Tone.mossSoft : Tone.signal.opacity(0.12), in: Capsule())
            .accessibilityLabel("Change versus the previous four weeks: \(text)")
    }
}

private struct MetricChart: View {
    let kind: MetricKind
    let points: [DailyMetric]
    let signal: BodySignal?
    var body: some View {
        Chart {
            if let signal {
                RectangleMark(xStart: .value("Start", points.first!.date), xEnd: .value("End", points.last!.date),
                              yStart: .value("Low", signal.low), yEnd: .value("High", signal.high))
                    .foregroundStyle(Tone.mossSoft.opacity(0.7))
            }
            ForEach(points) { point in
                if kind == .steps || kind == .sleepHours {
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value(kind.unit, point.value), width: .ratio(0.62))
                        .foregroundStyle(Tone.moss.opacity(0.55)).clipShape(Capsule())
                } else {
                    PointMark(x: .value("Day", point.date, unit: .day), y: .value(kind.unit, point.value))
                        .foregroundStyle(Tone.moss).symbolSize(22)
                }
            }
            ForEach(rolling) { point in
                LineMark(x: .value("Day", point.date, unit: .day), y: .value("7-day", point.value))
                    .foregroundStyle(Tone.ink).lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round)).interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: .automatic(includesZero: kind == .steps || kind == .sleepHours))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Tone.hairline)
                AxisValueLabel { if let v = value.as(Double.self) { Text(kind == .sleepMidpoint ? Format.clock(hours: v) : v.formatted(.number.notation(.compactName))).font(.caption2).foregroundStyle(Tone.ink3) } }
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.caption2).foregroundStyle(Tone.ink3)
            }
        }
        .accessibilityLabel("\(kind.title) daily values with seven-day average")
    }
    /// Seven-day rolling mean drawn only where at least four days exist.
    private struct Rolling: Identifiable { let date: Date; let value: Double; var id: Date { date } }
    private var rolling: [Rolling] {
        points.compactMap { point in
            let window = points.filter { $0.date <= point.date && $0.date > point.date.addingTimeInterval(-7 * 86400) }
            guard window.count >= 4, let mean = FitnessMath.mean(window.map(\.value)) else { return nil }
            return Rolling(date: point.date, value: mean)
        }
    }
}

private struct SourceCard: View {
    @EnvironmentObject private var library: AppStore
    let kind: MetricKind
    var body: some View {
        let options = library.sourceOptions(kind)
        if options.count > 1 {
            Card(padding: 14) {
                HStack {
                    Eyebrow("Source")
                    Spacer()
                    Menu {
                        ForEach(options, id: \.id) { option in
                            Button(option.name) { library.change { $0.sources[kind.rawValue] = option.id } }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(library.points(kind).first?.sourceName ?? "Choose").font(.subheadline.weight(.medium)).lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }.foregroundStyle(Tone.moss)
                    }
                }
            }
        }
    }
}

private struct TrainingTrendView: View {
    @EnvironmentObject private var library: AppStore
    var body: some View {
        let states = FitnessMath.training(library.data.workouts, days: 120)
        let recent = Array(states.suffix(56).drop { $0.fitness < 0.5 })
        Card {
            Eyebrow("Fitness · fatigue · form")
            if let today = states.last, library.data.workouts.contains(where: { $0.load != nil }) {
                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    stat("Form", today.form, signed: true)
                    stat("Fitness", today.fitness)
                    stat("Fatigue", today.fatigue)
                }.padding(.top, 8)
                Chart {
                    ForEach(recent) { state in
                        LineMark(x: .value("Day", state.date, unit: .day), y: .value("Fitness", state.fitness), series: .value("S", "Fitness"))
                            .foregroundStyle(Tone.moss).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round)).interpolationMethod(.monotone)
                        LineMark(x: .value("Day", state.date, unit: .day), y: .value("Fatigue", state.fatigue), series: .value("S", "Fatigue"))
                            .foregroundStyle(Tone.ink3).lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3])).interpolationMethod(.monotone)
                    }
                }
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(Tone.hairline); AxisValueLabel().font(.caption2).foregroundStyle(Tone.ink3) } }
                .chartXAxis { AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.caption2).foregroundStyle(Tone.ink3) } }
                .frame(height: 170).padding(.top, 14)
                HStack(spacing: 14) { legend(Tone.moss, "Fitness · 42-day"); legend(Tone.ink3, "Fatigue · 7-day") }.padding(.top, 10)
                Text("Positive form means recent load is below what you’re adapted to; negative form follows a hard block.").font(.footnote).foregroundStyle(Tone.ink2).padding(.top, 10)
            } else {
                Text("Rate how hard each session felt (0–10). Load = effort × minutes feeds a fitness–fatigue model.").font(.subheadline).foregroundStyle(Tone.ink2).padding(.top, 8)
            }
        }
        WorkloadCard()
        WeeklyLoadCard()
        CardioCard()
        Card(padding: 6) {
            NavigationLink { SessionsList() } label: {
                HStack {
                    Label("Sessions", systemImage: "list.bullet").font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(library.data.workouts.count)").foregroundStyle(Tone.ink3)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Tone.ink3)
                }.padding(12).foregroundStyle(Tone.ink)
            }.buttonStyle(PressStyle())
        }
    }
    private func stat(_ label: String, _ value: Double, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(signed ? Format.signed(value) : value.formatted(.number.precision(.fractionLength(0)))).font(.figure(34)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Tone.ink2)
        }
    }
    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) { Capsule().fill(color).frame(width: 12, height: 4); Text(text).font(.caption2).foregroundStyle(Tone.ink2) }
    }
}

private struct WeeklyLoadCard: View {
    @EnvironmentObject private var library: AppStore
    private struct Week: Identifiable { let start: Date; let load: Double; var id: Date { start } }
    var body: some View {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
        let weeks = (0..<8).reversed().map { offset -> Week in
            let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek)!
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            return Week(start: start, load: library.data.workouts.filter { $0.date >= start && $0.date < end }.compactMap(\.load).reduce(0, +))
        }
        if weeks.contains(where: { $0.load > 0 }) {
            Card {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("Weekly load")
                    Spacer()
                    Text("\(Int(weeks.last!.load)) this week").font(.caption).foregroundStyle(Tone.ink2)
                }
                Chart(weeks) { week in
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Load", week.load), width: .ratio(0.55))
                        .foregroundStyle(week.start == thisWeek ? Tone.moss : Tone.moss.opacity(0.35)).clipShape(Capsule())
                }
                .chartYAxis(.hidden)
                .chartXAxis { AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.caption2).foregroundStyle(Tone.ink3) } }
                .frame(height: 110).padding(.top, 12)
            }
        }
    }
}

/// Acute:chronic workload ratio and weekly ramp.
private struct WorkloadCard: View {
    @EnvironmentObject private var library: AppStore
    var body: some View {
        let ratio = FitnessMath.workloadRatio(library.data.workouts)
        if let value = ratio.ratio {
            let balanced = value >= 0.8 && value <= 1.3
            Card {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("Workload ratio")
                    Spacer()
                    Text(ratio.zone).font(.caption.weight(.semibold)).padding(.horizontal, 8).frame(height: 24)
                        .foregroundStyle(balanced ? Tone.moss : Tone.signal)
                        .background((balanced ? Tone.mossSoft : Tone.signal.opacity(0.12)), in: Capsule())
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value.formatted(.number.precision(.fractionLength(2)))).font(.figure(44)).monospacedDigit()
                    Text("acute ÷ chronic").font(.subheadline).foregroundStyle(Tone.ink2)
                    Spacer()
                    if let ramp = FitnessMath.weeklyRamp(library.data.workouts) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Format.signed(ramp) + "%").font(.figure(20)).monospacedDigit().foregroundStyle(abs(ramp) > 50 ? Tone.signal : Tone.ink)
                            Text("week ramp").font(.caption2).foregroundStyle(Tone.ink3)
                        }
                    }
                }.padding(.top, 4)
                RangeBar(low: 0.8, high: 1.3, value: value, outside: !balanced).padding(.top, 10)
                Text("7-day load against your 28-day average (Williams et al., 2017). The 0.8–1.3 band is the common “sweet spot”; the ratio is debated, so treat it as context.").font(.caption).foregroundStyle(Tone.ink3).padding(.top, 10)
            }
        }
    }
}

/// Heart-rate-ratio fitness estimate and training zones from age and resting HR.
struct CardioCard: View {
    @EnvironmentObject private var library: AppStore
    var body: some View {
        let resting = FitnessMath.trend(library.points(.restingPulse)).recent ?? library.points(.restingPulse).last?.value
        let maximum = library.data.profile.maximumHeartRate.map(Double.init) ?? library.data.profile.age.map(FitnessMath.maximumHeartRate)
        Card {
            Eyebrow("Cardio fitness")
            if let resting, let maximum, let vo2 = FitnessMath.cardioFitness(maximum: maximum, resting: resting) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("≈ \(Int(vo2.rounded()))").font(.figure(40)).monospacedDigit()
                    Text("ml/kg/min VO₂max").font(.subheadline).foregroundStyle(Tone.ink2)
                    Spacer()
                    if let age = library.data.profile.age, let category = FitnessMath.cardioCategory(vo2: vo2, age: age, sex: library.data.profile.sex) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(category.label).font(.subheadline.weight(.semibold)).foregroundStyle(Tone.moss)
                            Text("~\(category.percentile)th pct").font(.caption2).foregroundStyle(Tone.ink3)
                        }
                    }
                }.padding(.top, 6)
                Text(library.data.profile.sex == .unspecified ? "Estimated from max \(Int(maximum)) and resting \(Int(resting.rounded())) bpm. Add your sex in Profile for an age-matched percentile." : "Estimated from max \(Int(maximum)) and resting \(Int(resting.rounded())) bpm, ranked against age and sex norms. Expect ±10–15% error.").font(.caption).foregroundStyle(Tone.ink3)
                let floors = FitnessMath.zoneFloors(maximum: maximum, resting: resting)
                VStack(spacing: 6) {
                    ForEach(Array(floors.enumerated()), id: \.offset) { index, floor in
                        let ceiling = index + 1 < floors.count ? floors[index + 1] : maximum
                        HStack {
                            Text("Zone \(index + 1)").font(.footnote.weight(.medium))
                            Capsule().fill(Tone.moss.opacity(0.25 + Double(index) * 0.18)).frame(height: 6)
                            Text("\(Int(floor))–\(Int(ceiling))").font(.footnote).monospacedDigit().foregroundStyle(Tone.ink2).frame(width: 70, alignment: .trailing)
                        }
                    }
                }.padding(.top, 14)
            } else {
                Text(library.data.profile.age == nil ? "Add your age in Band → Profile and import resting heart rate to estimate VO₂max and zones." : "Import resting heart rate from Apple Health to estimate VO₂max and zones.")
                    .font(.subheadline).foregroundStyle(Tone.ink2).padding(.top, 8)
            }
        }
    }
}

struct SessionsList: View {
    @EnvironmentObject private var library: AppStore
    @State private var editing: WorkoutEntry?
    var body: some View {
        List {
            ForEach(library.data.workouts.sorted { $0.date > $1.date }) { workout in
                Button { editing = workout } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workout.activity).font(.body.weight(.medium))
                            Text("\(workout.date.formatted(date: .abbreviated, time: .shortened)) · \(Int(workout.minutes)) min · \(workout.source)").font(.caption).foregroundStyle(Tone.ink2)
                        }
                        Spacer()
                        if let load = workout.load { Text("\(Int(load))").font(.figure(20)).monospacedDigit() }
                        else { Text("Rate").font(.caption.weight(.semibold)).foregroundStyle(Tone.moss) }
                    }.foregroundStyle(Tone.ink)
                }
                .swipeActions { Button("Delete", role: .destructive) { library.change { $0.workouts.removeAll { $0.id == workout.id } } } }
            }
            .listRowBackground(Tone.surface)
        }
        .surfaceRows()
        .overlay { if library.data.workouts.isEmpty { ContentUnavailableView("No sessions", systemImage: "figure.run", description: Text("Start or log a session from Today.")) } }
        .navigationTitle("Sessions")
        .sheet(item: $editing) { LogWorkoutSheet(existing: $0) }
    }
}
