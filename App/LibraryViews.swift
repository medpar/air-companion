import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var library: AppStore
    @State private var metric = MetricKind.restingPulse
    @State private var days = 28
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Metric", selection: $metric) { ForEach(MetricKind.allCases) { Text($0.title).tag($0) } }
                    Picker("Range", selection: $days) { Text("4 weeks").tag(28); Text("8 weeks").tag(56) }.pickerStyle(.segmented)
                }
                let points = library.points(metric)
                let visible = points.filter { $0.date >= Calendar.current.date(byAdding: .day, value: -days, to: Date())! }
                let trend = FitnessMath.trend(points)
                Section {
                    if visible.isEmpty {
                        ContentUnavailableView("A little history helps", systemImage: metric.symbol, description: Text(metric == .steps ? "Refresh your Air to save daily step snapshots." : "Import Apple Health data in My Air to see this trend."))
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(metric.title).font(.headline)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(trend.recent.map { $0.formatted(.number.precision(.fractionLength(metric == .sleepHours ? 1 : 0))) } ?? "—")
                                    .font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                                Text(metric.unit).foregroundStyle(.secondary)
                            }
                            Text("7-day average · \(trend.recentDays) days recorded").font(.caption).foregroundStyle(.secondary)
                            Chart(visible) { point in
                                // Dots keep gaps honest; no invented connecting measurements.
                                PointMark(x: .value("Day", point.date), y: .value(metric.unit, point.value)).foregroundStyle(airTint)
                            }
                            .chartYScale(domain: .automatic(includesZero: metric == .steps))
                            .chartXScale(range: .plotDimension(padding: 12))
                            .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear)) { value in AxisGridLine(); AxisValueLabel(format: .dateTime.day()) } }
                            .frame(height: 190)
                            Text(points.first?.sourceName ?? "").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                }
                Section("Your baseline") {
                    LabeledContent("Previous 28 days", value: trend.baseline.map { "\($0.formatted(.number.precision(.fractionLength(1)))) \(metric.unit)" } ?? "Not enough data")
                    LabeledContent("Days recorded", value: "\(trend.baselineDays) / 28")
                    if let delta = trend.delta {
                        LabeledContent("Recent change", value: "\(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1)))) \(metric.unit)")
                    } else {
                        Text("A comparison needs 4 recent days and 14 baseline days.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    SourcePicker(kind: metric)
                    NavigationLink("How this is calculated") { DataQualityView() }
                    NavigationLink("Daily values") {
                        List(points.reversed()) { point in
                            LabeledContent(point.date.formatted(date: .abbreviated, time: .omitted), value: "\(point.value.formatted(.number.precision(.fractionLength(metric == .steps ? 0 : 1)))) \(metric.unit)")
                        }.navigationTitle(metric.title)
                    }
                }
            }.navigationTitle("Trends")
        }
    }
}
private struct SourcePicker: View {
    @EnvironmentObject private var library: AppStore
    let kind: MetricKind
    var body: some View {
        let candidates = library.data.metrics.filter { $0.kind == kind }
        let sources = Dictionary(candidates.map { ($0.sourceID, $0.sourceName) }, uniquingKeysWith: { first, _ in first })
        let ordered = sources.keys.sorted { sources[$0]! < sources[$1]! }
        if !ordered.isEmpty {
            Picker("Source", selection: Binding(get: { let preferred = library.data.sources[kind.rawValue]; return preferred.flatMap { sources[$0] == nil ? nil : $0 } ?? ordered.first! }, set: { value in _ = library.change { $0.sources[kind.rawValue] = value } })) {
                ForEach(ordered, id: \.self) { Text(sources[$0]!).tag($0) }
            }
        }
    }
}

struct HealthSettingsView: View {
    @EnvironmentObject private var library: AppStore
    @EnvironmentObject private var health: HealthImport
    @State private var removing = false
    var body: some View {
        Form {
            Section {
                Label("Your history, on your iPhone", systemImage: "heart.text.clipboard").font(.headline)
                Text("Read sleep, resting heart rate, HRV and workouts from the past 60 days. Each metric keeps its source; nothing is written back to Health.")
                    .foregroundStyle(.secondary)
                Button { health.refresh(into: library) } label: {
                    HStack { Text(health.busy ? "Importing…" : "Connect & refresh Apple Health"); Spacer(); if health.busy { ProgressView() } }
                }.disabled(health.busy || library.preview)
                if let date = library.data.healthReadAt { LabeledContent("Last import", value: date.formatted(date: .abbreviated, time: .shortened)) }
                if let message = health.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            Section { ForEach(MetricKind.allCases) { kind in SourcePicker(kind: kind) } } header: { Text("Sources") } footer: {
                Text("A Google Health import requires that app to write the relevant data to Apple Health. Access to Health does not imply access to your Air’s full history.")
            }
            Section {
                Button("Remove imported health history", role: .destructive) { removing = true }.disabled(health.busy)
                Text("Your manual workouts and Air snapshots are kept. Revoke Health permissions separately in the Health app.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Apple Health").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Remove imported history from this app?", isPresented: $removing, titleVisibility: .visible) {
                Button("Remove history", role: .destructive) { _ = library.change { data in data.metrics.removeAll { $0.sourceID != "air" }; data.workouts.removeAll { $0.source != "Manual" }; data.healthReadAt = nil; data.sources = [:] } }
            }
    }
}

struct WorkoutsView: View {
    @EnvironmentObject private var library: AppStore
    @State private var editing: WorkoutEntry?
    @State private var adding = false
    @State private var timer = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("This week").font(.headline)
                        HStack(alignment: .firstTextBaseline) {
                            Text(Int(FitnessMath.weeklyLoad(library.data.workouts)).formatted()).font(.system(size: 48, weight: .semibold, design: .rounded))
                            Text("load · AU").foregroundStyle(.secondary)
                        }
                        Text("Duration × session effort").font(.footnote).foregroundStyle(.secondary)
                        Button {
                            if library.data.session == nil { _ = library.change { $0.session = WorkoutSession() } }
                            timer = library.data.session != nil
                        } label: { Label(library.data.session == nil ? "Start a session" : "Return to session", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                    }.padding(.vertical, 8)
                }
                Section("Recent sessions") {
                    if library.data.workouts.isEmpty { ContentUnavailableView("Make room for movement", systemImage: "figure.run", description: Text("Log a session or import workouts from Apple Health.")) }
                    ForEach(library.data.workouts.sorted { $0.date > $1.date }) { workout in
                        Button { editing = workout } label: {
                            HStack(spacing: 14) {
                                Image(systemName: workout.activity == "Run" ? "figure.run" : "figure.mixed.cardio").font(.title2).foregroundStyle(airTint).frame(width: 30)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(workout.activity).font(.headline).foregroundStyle(.primary)
                                    Text("\(workout.date.formatted(date: .abbreviated, time: .omitted)) · \(Int(workout.minutes)) min").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(workout.load.map { "\(Int($0)) AU" } ?? "Add effort").font(.subheadline).foregroundStyle(workout.load == nil ? airTint : .primary)
                                    Text(workout.source).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }.padding(.vertical, 5)
                        }.buttonStyle(.plain)
                    }
                }
                Section {
                    NavigationLink("Training-load method") { DataQualityView() }
                    Text("Imported sessions need an effort rating before they contribute to load. If you log a workout manually and later import the same workout, remove one entry to avoid double counting.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Activity")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Log workout", systemImage: "plus") { adding = true } } }
                .sheet(isPresented: $adding) { WorkoutEditor(workout: WorkoutEntry(id: UUID(), date: Date(), activity: "Run", minutes: 30, effort: nil, note: "", source: "Manual")) }
                .sheet(item: $editing) { WorkoutEditor(workout: $0) }
                .sheet(isPresented: $timer) { SessionTimerView() }
        }
    }
}
private struct SessionTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: AppStore
    @State private var completed: WorkoutEntry?
    @State private var discard = false
    private var running: Bool { library.data.session?.resumedAt != nil }
    private func elapsed(_ now: Date) -> TimeInterval { library.data.session?.elapsed(at: now) ?? 0 }
    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "figure.run").font(.system(size: 64)).foregroundStyle(airTint)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = Int(elapsed(context.date))
                    Text(String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)).font(.system(size: 48, weight: .medium, design: .rounded)).monospacedDigit()
                }
                Text(running ? "Session in progress" : "Paused").foregroundStyle(.secondary)
                Button(running ? "Pause" : "Resume") {
                    _ = library.change { data in
                        if running { data.session?.pause(at: Date()) }
                        else { data.session?.resume(at: Date()) }
                    }
                }.buttonStyle(.bordered).controlSize(.large)
                Button("Finish & log") {
                    if library.change({ $0.session?.pause(at: Date()) }) {
                        completed = WorkoutEntry(id: UUID(), date: library.data.session?.startedAt ?? Date(), activity: "Run", minutes: max(1, elapsed(Date()) / 60), effort: nil, note: "", source: "Manual")
                    }
                }.buttonStyle(.borderedProminent).controlSize(.large)
                Text("The timer survives closing the app and excludes pauses. It measures duration only; it does not start a workout on your band.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                Button("Discard session", role: .destructive) { discard = true }.font(.footnote)
                Spacer()
            }.padding().navigationTitle("Session").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .confirmationDialog("Discard this timer?", isPresented: $discard, titleVisibility: .visible) { Button("Discard", role: .destructive) { if library.change({ $0.session = nil }) { dismiss() } } }
                .sheet(item: $completed) { workout in WorkoutEditor(workout: workout, onSaved: { _ = library.change { $0.session = nil }; dismiss() }) }
                .interactiveDismissDisabled()
        }
    }
}
private struct WorkoutEditor: View {
    @EnvironmentObject private var library: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var workout: WorkoutEntry
    var onSaved: (() -> Void)?
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Activity", selection: $workout.activity) { ForEach(["Run", "Walk", "Ride", "Swim", "Strength", "Yoga", "Workout"], id: \.self) { Text($0) } }
                    DatePicker("Date", selection: $workout.date, in: ...Date())
                    HStack { Text("Minutes"); Spacer(); TextField("Duration", value: $workout.minutes, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                }
                Section("Whole-session effort") {
                    Picker("Effort", selection: Binding(get: { workout.effort ?? -1 }, set: { workout.effort = $0 < 0 ? nil : $0 })) {
                        Text("Not rated").tag(-1)
                        ForEach(0...10, id: \.self) { value in Text("\(value) · \(effortName(value))").tag(value) }
                    }
                    LabeledContent("Training load", value: workout.load.map { "\(Int($0)) AU" } ?? "Needs an effort rating")
                    Text("Rate the entire session, ideally about 30 minutes after finishing. An easy warm-up and a hard finish count as one session.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Notes") { TextField("How did it feel?", text: $workout.note, axis: .vertical).lineLimit(3...6) }
                Section { LabeledContent("Source", value: workout.source) }
                if library.data.workouts.contains(where: { $0.id == workout.id }) { Button("Delete from Air Companion", role: .destructive) { deleting = true } }
            }.navigationTitle("Workout").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        if library.change({ $0.workouts.removeAll { $0.id == workout.id }; $0.workouts.append(workout) }) { dismiss(); onSaved?() }
                    }.disabled(!workout.valid || workout.date > Date()) }
                }
                .confirmationDialog("Delete this local workout?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete", role: .destructive) { if library.change({ $0.workouts.removeAll { $0.id == workout.id } }) { dismiss() } } }
        }
    }
    private func effortName(_ value: Int) -> String {
        switch value { case 0: return "Rest"; case 1...2: return "Easy"; case 3...4: return "Moderate"; case 5...6: return "Hard"; case 7...8: return "Very hard"; case 9: return "Near maximum"; default: return "Maximum" }
    }
}

struct AutomationsView: View {
    @ObservedObject var band: BandConnection
    @EnvironmentObject private var library: AppStore
    @EnvironmentObject private var delivery: AutomationDelivery
    @State private var editing: AutomationRule?
    var body: some View {
        List {
            Section {
                Text("A small action at the right moment").font(.headline)
                Text("Celebrate your step goal after a refresh, or feel an incoming call while this app is open. Lights, other apps’ notifications and gestures remain unavailable.").font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Rules") {
                if library.data.rules.isEmpty { Text("Add your first rule.").foregroundStyle(.secondary) }
                ForEach(library.data.rules) { rule in
                    Button { editing = rule } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(rule.title).foregroundStyle(.primary)
                            Text(!rule.enabled ? "Off" : rule.canRun ? (rule.trigger == .incomingCall ? "On · while this app is open" : "On · checks after refresh") : "Draft · support required").font(.caption).foregroundStyle(rule.canRun && rule.enabled ? airTint : .secondary)
                        }.padding(.vertical, 4)
                    }
                }
            }
            if let message = delivery.message { Section { Text(message).font(.footnote).foregroundStyle(.secondary) } }
            Section("Recent events") {
                ForEach(library.data.receipts.sorted { $0.date > $1.date }.prefix(20)) { receipt in
                    VStack(alignment: .leading, spacing: 4) { Text(receipt.message).font(.subheadline); Text(receipt.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                }
                if library.data.receipts.isEmpty { Text("No events yet").foregroundStyle(.secondary) }
            }
        }.navigationTitle("Automations").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Add rule", systemImage: "plus") { editing = AutomationRule() } } }
            .sheet(item: $editing) { RuleEditor(band: band, rule: $0) }
    }
}
private struct RuleEditor: View {
    @ObservedObject var band: BandConnection
    @EnvironmentObject private var library: AppStore
    @EnvironmentObject private var delivery: AutomationDelivery
    @Environment(\.dismiss) private var dismiss
    @State var rule: AutomationRule
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("When", selection: $rule.trigger) { ForEach(RuleTrigger.allCases) { Text($0.title).tag($0) } }
                    Picker("Then", selection: $rule.action) { ForEach(RuleAction.allCases) { Text($0.title).tag($0) } }
                    Toggle("Enabled", isOn: $rule.enabled)
                }
                if rule.action == .bandVibration {
                    Section("Vibration") {
                        Picker("Pattern", selection: $rule.pattern) {
                            ForEach(["Short vibration", "Two groups", "Three groups"] + (rule.vibrationGroups == nil ? [rule.pattern] : []), id: \.self) { Text($0).tag($0) }
                        }
                        Text("Each group uses the Air’s intensity feedback and restores the original value. This does not control the motor’s exact waveform.").font(.footnote).foregroundStyle(.secondary)
                        if let groups = rule.vibrationGroups, !library.preview {
                            Button(band.active ? "Working…" : "Try on band", systemImage: "waveform") { band.testVibration(groups: groups) }
                                .disabled(!band.canPulse)
                            Text(band.status).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if rule.action == .bandLight { Section("Desired light") { Picker("Color", selection: $rule.light) { ForEach(["White", "Red"], id: \.self) { Text($0) } } } }
                if rule.action == .shortcut { Section("Shortcut") { TextField("Shortcut name", text: $rule.shortcut) } }
                Section {
                    Text(rule.executionNote)
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Preview in event log") { delivery.preview(rule, library: library) }
                }
                if library.data.rules.contains(where: { $0.id == rule.id }) { Button("Delete rule", role: .destructive) { if library.change({ $0.rules.removeAll { $0.id == rule.id } }) { dismiss() } } }
            }.navigationTitle("Automation").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(rule.canRun ? "Save" : "Save draft") { if library.change({ $0.rules.removeAll { $0.id == rule.id }; $0.rules.append(rule) }) { dismiss() } } }
                }
        }
    }
}
