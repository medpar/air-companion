import SwiftUI
import UniformTypeIdentifiers

@main
struct AirApp: App {
    @StateObject private var band = BandConnection()
    @StateObject private var library = AppStore()
    @StateObject private var health = HealthImport()
    @StateObject private var delivery = AutomationDelivery()
    @Environment(\.scenePhase) private var scene
    var body: some Scene {
        WindowGroup {
            AirView(band: band)
                .environmentObject(library).environmentObject(health).environmentObject(delivery)
                .onAppear {
                    if ProcessInfo.processInfo.arguments.contains("--preview") { library.setPreview(true); band.setPreview(true) }
                }
                .onChange(of: band.activityUpdateID) { _, _ in
                    guard let reading = band.activity, !library.preview else { return }
                    if let steps = reading.steps {
                        _ = library.change { data in
                            let day = Calendar.current.startOfDay(for: reading.readAt)
                            data.metrics.removeAll { $0.kind == .steps && $0.sourceID == "air" && $0.date == day }
                            data.metrics.append(DailyMetric(kind: .steps, date: day, value: Double(steps), sourceID: "air", sourceName: "Fitbit Air · refresh snapshot"))
                        }
                    }
                    delivery.evaluate(library: library, reading: reading)
                }
                .alert("Couldn’t save", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) { Button("OK") { library.error = nil } } message: { Text(library.error ?? "") }
                .onChange(of: scene) { _, state in
                    if state == .active { band.refreshKeys() }
                    else if state == .background { band.stop() }
                }
        }
    }
}

let airTint = Color(red: 0.08, green: 0.46, blue: 0.39)
struct AirView: View {
    @EnvironmentObject private var library: AppStore
    @State private var selected = 0
    @ObservedObject var band: BandConnection
    var body: some View {
        VStack(spacing: 0) {
            if library.preview {
                HStack {
                    Image(systemName: "play.rectangle"); Text("Preview · Example data"); Spacer()
                    Button("Exit") { library.setPreview(false); band.setPreview(false) }
                }.font(.caption.weight(.medium)).padding(.horizontal).padding(.vertical, 8).background(.yellow.opacity(0.16))
            }
        TabView(selection: $selected) {
            TodayView(band: band).tabItem { Label("Today", systemImage: "circle.dotted.circle") }.tag(0)
            AlarmView(band: band).tabItem { Label("Alarms", systemImage: "alarm") }.tag(1)
            TrendsView().tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }.tag(2)
            WorkoutsView().tabItem { Label("Activity", systemImage: "figure.run") }.tag(3)
            BandView(band: band).tabItem { Label("My Air", systemImage: "sensor.tag.radiowaves.forward") }.tag(4)
        }
        }.tint(airTint)
            .onAppear {
                if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--tab"), ProcessInfo.processInfo.arguments.count > index + 1 { selected = Int(ProcessInfo.processInfo.arguments[index + 1]) ?? 0 }
            }
    }
}

private struct ConnectionRow: View {
    @ObservedObject var band: BandConnection
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if band.active { ProgressView() }
                else { Image(systemName: band.lastRead == nil ? "link" : "checkmark.circle.fill").foregroundStyle(airTint) }
                Text(band.status).font(.subheadline.weight(.semibold))
                Spacer()
                Button(band.active ? "Stop" : "Refresh") { band.active ? band.stop() : band.start() }
                    .font(.subheadline.weight(.semibold)).buttonStyle(.borderless)
            }
            Text(band.detail).font(.footnote).foregroundStyle(.secondary)
        }.padding(.vertical, 5)
    }
}

private struct TodayView: View {
    @ObservedObject var band: BandConnection
    @EnvironmentObject private var library: AppStore
    @EnvironmentObject private var delivery: AutomationDelivery
    private var goal: Int { library.data.goal }
    @State private var showGoal = false
    private var todaySteps: Int? {
        guard let reading = band.activity, Calendar.current.isDateInToday(reading.readAt) else { return nil }
        return reading.steps
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Label("Steps", systemImage: "figure.walk").font(.headline)
                            Spacer()
                            Button("Goal") { showGoal = true }.font(.subheadline)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(todaySteps.map { $0.formatted() } ?? "—")
                                .font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit()
                                .contentTransition(.numericText())
                            Text("/ \(goal.formatted())").font(.subheadline).foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(1, Double(todaySteps ?? 0) / Double(max(1, goal))))
                            .tint(airTint).accessibilityLabel("Daily step goal")
                        Text(band.activity == nil ? "Refresh to read activity from your Air." : "Last read \(band.activity!.readAt.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "heart.fill").foregroundStyle(.red).font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Heart rate").font(.headline)
                            Text(band.activity?.reliableHeartRate == true ? "Read \(band.activity!.readAt.formatted(date: .abbreviated, time: .shortened))" : "Waiting for a reliable reading")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let reading = band.activity, reading.reliableHeartRate, let pulse = reading.heartRate {
                            Text("\(pulse)").font(.title2.weight(.semibold)).monospacedDigit()
                            Text("bpm").font(.caption).foregroundStyle(.secondary)
                        } else { Text("—").font(.title2).foregroundStyle(.secondary) }
                    }.padding(.vertical, 6)
                }
                Section { ConnectionRow(band: band) } footer: {
                    if !library.preview { Text("Close Google Health before refreshing. Your Air keeps tracking between connections.") }
                }
                Section("This week") {
                    LabeledContent("Training load", value: "\(Int(FitnessMath.weeklyLoad(library.data.workouts))) AU")
                    Text("Session effort × minutes. Log a workout in Activity to track your week.").font(.footnote).foregroundStyle(.secondary)
                    if let message = delivery.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    NavigationLink { DataQualityView() } label: { Label("About your readings", systemImage: "waveform.path.ecg") }
                }
            }
            .navigationTitle("Today")
            .sheet(isPresented: $showGoal) {
                NavigationStack {
                    Form {
                        Section { Stepper("\(goal.formatted()) steps", value: Binding(get: { goal }, set: { value in _ = library.change { $0.goal = value } }), in: 1000...50000, step: 500) }
                        Section { Text("Set a target that suits you. Add an iPhone goal alert in My Air → Automations. Alerts run when you refresh; band vibration is not connected yet.").font(.footnote).foregroundStyle(.secondary) }
                    }.navigationTitle("Daily goal").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showGoal = false } } }
                }.presentationDetents([.medium])
            }
        }
    }
}

private struct AlarmView: View {
    @ObservedObject var band: BandConnection
    @State private var editing: BandAlarm?
    @State private var adding = false
    @State private var deleting: BandAlarm?
    var body: some View {
        NavigationStack {
            List {
                if let list = band.alarms {
                    Section {
                        ForEach(list.alarms) { alarm in
                            Button { editing = alarm } label: {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(alarm.time).font(.system(size: 44, weight: .light, design: .rounded)).monospacedDigit()
                                        Text(alarm.schedule + (alarm.smartWake ? " · Smart wake" : ""))
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(alarm.enabled ? "On" : "Off").font(.subheadline.weight(.medium))
                                        .foregroundStyle(alarm.enabled ? airTint : .secondary)
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                }.foregroundStyle(.primary).padding(.vertical, 8)
                            }.buttonStyle(.plain).disabled(band.active)
                                .swipeActions { Button("Delete", role: .destructive) { deleting = alarm } }
                        }
                    } header: { Text(band.preview ? "Example alarms" : "Last read from your Air") } footer: { Text("\(list.alarms.count) of \(list.maximum) alarms. Double-tap your band to dismiss a ringing alarm.") }
                } else {
                    ContentUnavailableView("No alarms loaded", systemImage: "alarm", description: Text("Refresh once to see the alarms saved on your Air."))
                        .listRowBackground(Color.clear)
                }
                Section { ConnectionRow(band: band) } footer: { Text(band.preview ? "Preview changes stay in memory. Exit preview to return to your saved alarms." : "Changes are saved directly to your band and checked automatically.") }
            }
            .navigationTitle("Alarms")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Add alarm", systemImage: "plus") { adding = true }.disabled(band.active || band.alarms == nil || (band.alarms?.alarms.count ?? 0) >= (band.alarms?.maximum ?? 0)) } }
            .sheet(isPresented: $adding) { AlarmEditor(band: band, alarm: nil) }
            .confirmationDialog("Delete this alarm from your Air?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete alarm", role: .destructive) { if let deleting { band.delete(deleting) }; deleting = nil }
            }
            .sheet(item: $editing) { alarm in AlarmEditor(band: band, alarm: alarm) }
        }
    }
}

private struct AlarmEditor: View {
    @ObservedObject var band: BandConnection
    let alarm: BandAlarm?
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date
    @State private var enabled: Bool
    @State private var smartWake: Bool
    @State private var days: UInt8
    init(band: BandConnection, alarm: BandAlarm?) {
        self.band = band; self.alarm = alarm
        _time = State(initialValue: Calendar.current.date(from: DateComponents(hour: alarm?.hour ?? 7, minute: alarm?.minute ?? 0)) ?? Date())
        _enabled = State(initialValue: alarm?.enabled ?? true); _smartWake = State(initialValue: alarm?.smartWake ?? false)
        _days = State(initialValue: alarm?.recurring == true ? alarm!.days : 0)
    }
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                Section {
                    Toggle("Enabled", isOn: $enabled)
                    if band.alarms?.smartWakeSupported == true { Toggle("Smart wake", isOn: $smartWake) }
                    NavigationLink {
                        List {
                            ForEach(Array(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"].enumerated()), id: \.offset) { index, name in
                                Button { days ^= UInt8(1 << index) } label: {
                                    HStack { Text(name).foregroundStyle(.primary); Spacer(); if days & UInt8(1 << index) != 0 { Image(systemName: "checkmark") } }
                                }
                            }
                            Button("Never repeat") { days = 0 }
                        }.navigationTitle("Repeat")
                    } label: { LabeledContent("Repeat", value: days == 0 ? "Never" : days == 127 ? "Every day" : "\(days.nonzeroBitCount) days") }
                } footer: { Text("Times follow your band’s clock. Existing snooze behavior is preserved. Close Google Health before saving. Changes are checked against a fresh read.") }
            }
            .navigationTitle(alarm == nil ? "New alarm" : "Edit alarm").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                        if let alarm { band.save(alarm, hour: parts.hour ?? alarm.hour, minute: parts.minute ?? alarm.minute, enabled: enabled, smartWake: smartWake, days: days) }
                        else { band.create(AlarmDraft(hour: parts.hour ?? 7, minute: parts.minute ?? 0, enabled: enabled, smartWake: smartWake, days: days)) }
                        dismiss()
                    }.fontWeight(.semibold).disabled(band.active)
                }
            }
        }
    }
}

private struct BandView: View {
    @EnvironmentObject private var library: AppStore
    @EnvironmentObject private var health: HealthImport
    @State private var importing = false
    @State private var importMessage: String?
    @ObservedObject var band: BandConnection
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "sensor.tag.radiowaves.forward.fill").font(.largeTitle).foregroundStyle(airTint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fitbit Air").font(.headline)
                            Label(band.keysReady ? "Secure connection ready" : "Device key needed", systemImage: band.keysReady ? "lock.shield" : "key")
                                .font(.footnote).foregroundStyle(.secondary)
                        }.padding(.vertical, 10)
                    }
                    ConnectionRow(band: band)
                }
                Section {
                    NavigationLink { AutomationsView() } label: { Label("Automations", systemImage: "bolt") }
                    NavigationLink { HealthSettingsView() } label: { Label("Apple Health", systemImage: "heart.text.clipboard") }
                    NavigationLink { DataQualityView() } label: { Label("Methods & privacy", systemImage: "hand.raised") }
                }
                Section("Vibration") {
                    LabeledContent("Intensity options", value: band.capabilities?.hapticSummary ?? "Refresh to check")
                    if let haptic = band.haptic, !library.preview {
                        Picker("Intensity", selection: Binding(get: { haptic.intensity }, set: { band.setIntensity($0) })) {
                            ForEach((band.capabilities?.hapticIntensities ?? []).filter { (1...3).contains($0) }.sorted(), id: \.self) { Text(HapticSetting.name($0)).tag($0) }
                        }.disabled(band.active)
                    }
                    Text("Intensity controls appear only after the band advertises support and returns its current setting. Custom patterns and step-goal vibrations still need a verified event route.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("iPhone notifications") {
                    LabeledContent("System sharing", value: band.notificationAccess ? "Authorized" : "Not authorized")
                    Text("Call and app notification vibrations are not enabled yet. They require a notification route supported by both iOS and your band.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Status light") {
                    Label("White · normal battery / charging", systemImage: "circle")
                    Label("Red · low battery", systemImage: "circle.fill").foregroundStyle(.red)
                    Text("Custom colors are not available in this build. The band’s documented status colors are white and red.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Double-tap") {
                    Label("Check battery or dismiss an alarm", systemImage: "hand.tap")
                    Text("Phone actions need an exported gesture event. That event has not been identified yet.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Development") {
                    Toggle("Preview with example data", isOn: Binding(get: { library.preview }, set: { enabled in library.setPreview(enabled); band.setPreview(enabled) })).disabled(band.active || health.busy)
                    Text("Preview changes stay in memory and never connect to your band.").font(.footnote).foregroundStyle(.secondary)
                    Button("Import device key") { importing = true }.disabled(library.preview || band.active)
                    if let importMessage { Text(importMessage).font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    Text("Air Companion · 0.2 development build").font(.footnote).foregroundStyle(.secondary)
                    Text("Your device keys stay in this iPhone’s Keychain. No account login or cloud service is used by this app.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("My Air")
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        guard data.count <= 16384 else { throw DeviceKeys.Failure.invalid }
                        let keys = try JSONDecoder().decode(DeviceKeys.self, from: data); try keys.validate()
                        let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("device-keys.json")
                        try data.write(to: destination, options: [.atomic, .completeFileProtection])
                        _ = try DeviceKeys.load(); band.refreshKeys(); importMessage = "Device keys stored in this iPhone’s Keychain. Delete your original import file when no longer needed."
                    } catch { importMessage = "Couldn’t import this key file. The app needs two valid Air device keys." }
                }
        }
    }
}

struct DataQualityView: View {
    var body: some View {
        List {
            Section("From your band") {
                Text("Steps and heart rate are snapshots requested directly from your Air. They do not replace a full history sync in Google Health. Old readings keep their timestamp; an old step count is never shown as today’s.")
                Text("Heart rate appears only when the band marks the reading as reliable. Missing data stays missing.")
            }
            Section("Trends") {
                Text("Each chart uses one selected data source. Daily HRV values are averages of SDNN samples from Apple Health, not RMSSD. Compare recordings under similar conditions.")
                Text("The recent average uses seven completed local days. The baseline uses the preceding 28 days. A comparison needs at least four recent days and 14 baseline days; it describes change, not readiness or a diagnosis.")
                Text("Sleep merges overlapping asleep stages from one source, excluding awake and in-bed time. Noon-to-noon windows keep overnight sleep together. Device estimates are not a clinical sleep study.")
            }
            Section("Training load") {
                Text("Session RPE load = duration in minutes × perceived effort (0–10). Add effort after the whole session, ideally about 30 minutes later. Sessions without an effort rating are excluded, not treated as zero. This is a training log, not an injury-risk prediction.")
                Link("Foster et al. · Session RPE", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/11708692/")!)
                Link("HRV measurement standards", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/8598068/")!)
                Link("HRV collection recommendations", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/30852243/")!)
            }
            Section("Privacy") {
                Text("No analytics, advertising or cloud account. Keys live in device-only Keychain storage. Health history, workouts and alarm backups use protected files on this iPhone. Apple’s device backup settings may include these files. Preview examples are never written to your real library.")
                Text("Apple Health access is read-only. You can revoke it in the Health app. Removing access does not erase previously imported history.")
            }
            Section("Development status") {
                Text("A real Air alarm read has succeeded. Alarm writes, activity reads and later reconnections still need device testing. Custom band vibration, light colors, iPhone notification forwarding and gesture events have no verified Air transport yet. Saved rules cannot enable missing firmware capabilities.")
            }
        }.navigationTitle("Methods & privacy").navigationBarTitleDisplayMode(.inline)
    }
}
