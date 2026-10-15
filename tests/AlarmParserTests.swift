import Foundation
@main struct AlarmParserTests {
    static func variable(_ value: UInt64) -> Data {
        var value = value, data = Data()
        repeat { var byte = UInt8(value & 127); value >>= 7; if value > 0 { byte |= 128 }; data.append(byte) } while value > 0
        return data
    }
    static func int(_ field: UInt64, _ value: UInt64) -> Data { variable(field << 3) + variable(value) }
    static func bytes(_ field: UInt64, _ body: Data) -> Data { variable((field << 3) | 2) + variable(UInt64(body.count)) + body }
    static func reject(_ data: Data) {
        do { _ = try AlarmList(data: data); fatalError("Accepted invalid alarm message") } catch {}
    }
    static func main() throws {
        let capabilities = bytes(1, int(1, 8) + int(2, 1))
        let config = int(1, 1) + int(3, 1) + bytes(5, int(1, 7) + int(2, 30)) + bytes(6, Data([31]))
        let alarm = bytes(2, int(1, 3) + bytes(2, config))
        let parsed = try AlarmList(data: capabilities + alarm)
        precondition(parsed.maximum == 8 && parsed.smartWakeSupported && parsed.alarms.count == 1)
        precondition(parsed.alarms[0].time == "07:30" && parsed.alarms[0].days == 31 && parsed.alarms[0].smartWake)
        let protectedConfig = config + int(2, 1) + int(4, 1) + bytes(70, Data([9, 8, 7]))
        let protectedAlarm = try AlarmList(data: capabilities + bytes(2, int(1, 3) + bytes(2, protectedConfig))).alarms[0]
        let edited = try protectedAlarm.edited(hour: 8, minute: 45, enabled: false, smartWake: false)
        let editedProto = try Proto(edited), originalProto = try Proto(protectedConfig)
        for field in [2, 4, 6, 70] { precondition(editedProto.fields[field] == originalProto.fields[field]) }
        let editedList = try AlarmList(data: capabilities + bytes(2, int(1, 3) + bytes(2, edited)))
        precondition(editedList.alarms[0].time == "08:45" && !editedList.alarms[0].enabled && !editedList.alarms[0].smartWake)
        let changedSchedule = try protectedAlarm.edited(hour: 6, minute: 15, enabled: true, smartWake: false, days: 96)
        let scheduleProto = try Proto(changedSchedule)
        let recurring = try scheduleProto.oneBool(4); precondition(recurring)
        let weekend = try scheduleProto.oneBytes(6); precondition(weekend == Data([96]))
        let snooze = try scheduleProto.oneBool(2); precondition(snooze) // preserve snooze
        func list(_ entries: [(UInt64, Data)]) throws -> AlarmList {
            try AlarmList(data: capabilities + entries.reduce(Data()) { $0 + bytes(2, int(1, $1.0) + bytes(2, $1.1)) })
        }
        let original = try list([(3, protectedConfig), (5, config)])
        func check(_ value: Bool) { precondition(value) }
        let change = AlarmChange.edit(original.alarms[0], edited)
        check(change.validate(before: original))
        try check(change.verified(before: original, after: list([(3, edited), (5, config)])))
        try check(!change.verified(before: original, after: list([(3, edited), (5, edited)])))
        try check(!change.validate(before: list([(3, edited), (5, config)])))
        let newConfig = try AlarmDraft(hour: 8, minute: 0, enabled: true, smartWake: false, days: 127).configuration()
        let creation = AlarmChange.create(newConfig)
        try check(creation.verified(before: original, after: list([(3, protectedConfig), (5, config), (8, newConfig)])))
        check(!creation.verified(before: original, after: original))
        check(!creation.validate(before: AlarmList(maximum: 2, smartWakeSupported: true, alarms: original.alarms)))
        let disabled = try AlarmDraft(hour: 12, minute: 34, enabled: false, smartWake: false).configuration()
        let forcedEnabled = try Proto(disabled).replacing(1, with: int(1, 1))
        let disabledCreation = AlarmChange.create(disabled)
        let forcedList = try list([(3, protectedConfig), (5, config), (0, forcedEnabled)])
        let correction = disabledCreation.activationCorrection(before: original, after: forcedList)
        precondition(correction?.0 == 0 && correction?.1 == disabled)
        try check(disabledCreation.activationCorrection(before: original, after: list([(3, edited), (5, config), (0, forcedEnabled)])) == nil)
        try check(disabledCreation.activationCorrection(before: original, after: list([(3, protectedConfig), (5, config), (0, edited)])) == nil)
        check(creation.activationCorrection(before: original, after: forcedList) == nil)
        let deletion = AlarmChange.delete(original.alarms[0])
        try check(deletion.verified(before: original, after: list([(5, config)])))
        try check(!deletion.verified(before: original, after: list([(5, edited)])))
        reject(bytes(1, int(1, UInt64.max))); reject(capabilities + alarm + alarm)
        reject(capabilities + bytes(2, bytes(2, bytes(5, int(1, 24)))))
        reject(bytes(1, int(1, 8) + int(2, 2)))
        reject(capabilities + bytes(2, bytes(2, int(1, 2) + bytes(5, Data()))))
        reject(Data([10, 255])); reject(Data(repeating: 128, count: 11))
        reject(Data([13, 8, 8, 16, 1])) // Capabilities must be length-delimited, not fixed32.
        reject(capabilities + bytes(1, int(1, 8)))
        let midnight = try AlarmList(data: capabilities + bytes(2, bytes(2, bytes(5, Data()))))
        precondition(midnight.alarms[0].time == "00:00")
        let hapticBody = int(1, 2) + bytes(70, Data([1, 2]))
        let haptic = try HapticSetting(data: bytes(1, bytes(1, hapticBody)))
        let hapticChanged = try HapticSetting(data: haptic.response(changingTo: 3))
        precondition(hapticChanged.intensity == 3)
        let unknownHaptic = try Proto(hapticChanged.configuration).fields[70]
        precondition(unknownHaptic == [.bytes(Data([1, 2]))])
        do { _ = try haptic.response(changingTo: 4); fatalError("Accepted unknown intensity") } catch {}
        let pulse = try HapticPulseTransaction(original: haptic, supported: [2, 3])
        precondition(pulse.recovery(for: haptic) == .alreadyRestored)
        precondition(pulse.recovery(for: hapticChanged) == .restore)
        let externalChange = try HapticSetting(data: bytes(1, bytes(1, int(1, 3) + bytes(70, Data([9])))))
        precondition(pulse.recovery(for: externalChange) == .conflict)
        let persistedPulse = try JSONDecoder().decode(HapticPulseTransaction.self, from: JSONEncoder().encode(pulse))
        precondition(persistedPulse.recovery(for: hapticChanged) == .restore)
        do { _ = try HapticPulseTransaction(original: haptic, supported: [2]); fatalError("Accepted unsupported alternate") } catch {}
        let off = try HapticSetting(data: haptic.response(changingTo: 1))
        do { _ = try HapticPulseTransaction(original: off, supported: [1, 2, 3]); fatalError("Overrode vibration off") } catch {}
        if CommandLine.arguments.count > 1 {
            let live = try AlarmList(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            precondition(live.maximum == 8 && live.smartWakeSupported && live.alarms.count == 2)
            print("PASS: private captured alarm response matches Swift decoder")
        }
        print("PASS: alarm bounds, overflow, invalid boolean, duplicates, midnight, truncation")
    }
}
