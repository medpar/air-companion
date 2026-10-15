import SwiftUI

struct AlarmsScreen: View {
    @EnvironmentObject private var band: BandConnection
    @State private var editing: BandAlarm?
    @State private var adding = false
    @State private var deleting: BandAlarm?

    var body: some View {
        NavigationStack {
            List {
                if let list = band.alarms {
                    Section {
                        ForEach(list.alarms) { alarm in
                            AlarmRow(alarm: alarm, busy: band.busy) { editing = alarm } toggle: { on in
                                band.save(alarm, hour: alarm.hour, minute: alarm.minute, enabled: on, smartWake: alarm.smartWake)
                            }
                            .swipeActions { Button("Delete", role: .destructive) { deleting = alarm }.disabled(band.busy) }
                        }
                    } footer: {
                        Text("\(list.alarms.count) of \(list.maximum) · Firmly double-tap the band to stop a ringing alarm.")
                            .font(.footnote).foregroundStyle(Tone.ink3).padding(.top, 6)
                    }
                    .listRowBackground(Tone.surface)
                } else {
                    ContentUnavailableView {
                        Label("No alarms yet", systemImage: "alarm")
                    } description: {
                        Text(band.keysReady ? "Pull down to read the alarms saved on your band." : "Connect your band in the Band tab.")
                    }
                    .listRowBackground(Color.clear)
                }
                if band.active || band.lastSucceeded == false {
                    Section { SyncLine() }.listRowBackground(Color.clear)
                }
            }
            .surfaceRows()
            .navigationTitle("Alarms")
            .refreshable { if band.canStart { _ = await band.run { band.start() } } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add alarm", systemImage: "plus") { adding = true }
                        .disabled(band.busy || band.alarms == nil || (band.alarms?.alarms.count ?? 0) >= (band.alarms?.maximum ?? 0))
                }
            }
            .sheet(isPresented: $adding) { AlarmEditor(alarm: nil) }
            .sheet(item: $editing) { AlarmEditor(alarm: $0) }
            .confirmationDialog("Delete this alarm from your band?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete alarm", role: .destructive) { if let deleting { band.delete(deleting) }; deleting = nil }
            }
        }
    }
}

private struct AlarmRow: View {
    let alarm: BandAlarm
    let busy: Bool
    let open: () -> Void
    let toggle: (Bool) -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(alarm.time).font(.figure(52, .light)).monospacedDigit()
                        .foregroundStyle(alarm.enabled ? Tone.ink : Tone.ink3)
                    Text(alarm.schedule + (alarm.smartWake ? " · Smart wake" : ""))
                        .font(.subheadline).foregroundStyle(Tone.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle()).disabled(busy)
            Toggle("Enabled", isOn: Binding(get: { alarm.enabled }, set: toggle)).labelsHidden().disabled(busy)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alarm.time), \(alarm.schedule), \(alarm.enabled ? "on" : "off")")
    }
}

struct SyncLine: View {
    @EnvironmentObject private var band: BandConnection
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if band.active { ProgressView().controlSize(.small) }
            else { Image(systemName: "exclamationmark.circle").foregroundStyle(Tone.signal) }
            VStack(alignment: .leading, spacing: 2) {
                Text(band.status).font(.subheadline.weight(.medium))
                Text(band.detail).font(.caption).foregroundStyle(Tone.ink2)
            }
        }
        .animation(.easeOut(duration: 0.2), value: band.status)
    }
}

struct AlarmEditor: View {
    @EnvironmentObject private var band: BandConnection
    @Environment(\.dismiss) private var dismiss
    let alarm: BandAlarm?
    @State private var time: Date
    @State private var enabled: Bool
    @State private var smartWake: Bool
    @State private var days: UInt8
    @State private var confirmDelete = false
    init(alarm: BandAlarm?) {
        self.alarm = alarm
        _time = State(initialValue: Calendar.current.date(from: DateComponents(hour: alarm?.hour ?? 7, minute: alarm?.minute ?? 0)) ?? Date())
        _enabled = State(initialValue: alarm?.enabled ?? true)
        _smartWake = State(initialValue: alarm?.smartWake ?? false)
        _days = State(initialValue: alarm?.recurring == true ? alarm!.days : 0)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                }
                Section {
                    DayPicker(days: $days)
                } header: { Text("Repeat") } footer: { Text(summary) }
                Section {
                    Toggle("Alarm on", isOn: $enabled)
                    if band.alarms?.smartWakeSupported == true {
                        Toggle(isOn: $smartWake) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Smart wake")
                                Text("May vibrate up to 30 min early, during lighter sleep.").font(.caption).foregroundStyle(Tone.ink2)
                            }
                        }
                    }
                } footer: {
                    if alarm == nil && !enabled { Text("Air turns new alarms on. Pebble switches it off right after and checks the result.") }
                }
                if alarm != nil {
                    Section { Button("Delete alarm", role: .destructive) { confirmDelete = true } }
                }
            }
            .surfaceRows()
            .navigationTitle(alarm == nil ? "New alarm" : "Edit alarm").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold).disabled(band.busy) }
            }
            .confirmationDialog("Delete this alarm from your band?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete alarm", role: .destructive) { if let alarm { band.delete(alarm) }; dismiss() }
            }
        }
    }
    private var summary: String {
        switch days {
        case 0: return "Rings once."
        case 127: return "Every day."
        case 31: return "Weekdays."
        case 96: return "Weekends."
        default: return "\(days.nonzeroBitCount) days a week."
        }
    }
    private func save() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = parts.hour ?? 7, minute = parts.minute ?? 0
        if let alarm { band.save(alarm, hour: hour, minute: minute, enabled: enabled, smartWake: smartWake, days: days) }
        else { band.create(AlarmDraft(hour: hour, minute: minute, enabled: enabled, smartWake: smartWake, days: days)) }
        dismiss()
    }
}

/// Seven round day toggles, Monday first (bit 0) to match the band.
struct DayPicker: View {
    @Binding var days: UInt8
    private let letters = ["M", "T", "W", "T", "F", "S", "S"]
    private let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                let on = days & UInt8(1 << index) != 0
                Button { days ^= UInt8(1 << index) } label: {
                    Text(letters[index]).font(.subheadline.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(on ? Tone.onMoss : Tone.ink)
                        .background(on ? Tone.moss : Tone.sunken, in: Circle())
                }
                .buttonStyle(PressStyle())
                .frame(maxWidth: .infinity)
                .accessibilityLabel(names[index]).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: days)
    }
}
