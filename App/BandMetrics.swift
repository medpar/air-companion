import Foundation

struct BandCapabilities {
    let settings: Set<UInt64>
    let hapticIntensities: Set<UInt64>
    let goalTypes: Set<UInt64>
    init(data: Data) throws {
        let body = try Proto(data)
        settings = Set(try body.integers(1))
        hapticIntensities = Set(try body.integers(2))
        goalTypes = Set(try body.integers(3))
    }
    var hapticSummary: String {
        guard settings.contains(1) else { return "Not advertised by your band" }
        let labels: [UInt64: String] = [1: "Off", 2: "Low", 3: "High"]
        return hapticIntensities.sorted().compactMap { labels[$0] }.joined(separator: ", ")
    }
}

struct ActivityReading: Codable {
    let readAt: Date
    let steps: Int?
    let heartRate: Int?
    let reliableHeartRate: Bool
    init(data: Data) throws {
        let body = try Proto(data)
        let count = try body.oneInt(2), pulse = try body.oneInt(7)
        let confidence = try body.oneInt(8)
        guard count <= 1_000_000, pulse <= 300, confidence <= 3 else { throw Proto.Failure.invalid }
        readAt = Date()
        steps = body.fields[2] == nil ? nil : Int(count)
        heartRate = body.fields[7] == nil || pulse == 0 ? nil : Int(pulse)
        reliableHeartRate = confidence >= 2
    }
}

struct HapticSetting: Codable {
    let intensity: UInt64
    let configuration: Data
    init(data: Data) throws {
        let response = try Proto(data)
        let settings = try response.bytes(1).map(Proto.init)
        let haptics = try settings.filter { $0.fields[1] != nil }.map { try $0.oneBytes(1, required: true) }
        guard haptics.count == 1 else { throw Proto.Failure.invalid }
        configuration = haptics[0]
        intensity = try Proto(configuration).oneInt(1)
        guard (1...3).contains(intensity) else { throw Proto.Failure.invalid }
    }
    func response(changingTo value: UInt64) throws -> Data {
        guard (1...3).contains(value) else { throw Proto.Failure.invalid }
        let updated = try Proto(configuration).replacing(1, with: Proto.integer(1, value))
        return Proto.message(1, Proto.message(1, updated))
    }
    static func name(_ value: UInt64) -> String { [1: "Off", 2: "Low", 3: "High"][value] ?? "Unknown" }
    func matches(_ other: HapticSetting) -> Bool {
        guard let first = try? Proto(configuration).fields, let second = try? Proto(other.configuration).fields else { return false }
        return first == second
    }
}

/// A short feedback group uses the band's normal intensity preview. It is not
/// an arbitrary motor waveform. Persist this before the first setting write.
struct HapticPulseTransaction: Codable {
    let original: HapticSetting
    let alternate: HapticSetting
    let createdAt: Date
    enum Recovery: Equatable { case alreadyRestored, restore, conflict }
    init(original: HapticSetting, supported: Set<UInt64>) throws {
        guard [2, 3].contains(original.intensity), supported.isSuperset(of: [2, 3]) else { throw Proto.Failure.invalid }
        self.original = original
        alternate = try HapticSetting(data: original.response(changingTo: original.intensity == 2 ? 3 : 2))
        createdAt = Date()
    }
    func recovery(for current: HapticSetting) -> Recovery {
        if current.matches(original) { return .alreadyRestored }
        if current.matches(alternate) { return .restore }
        return .conflict // Another app/user may have changed it; never overwrite.
    }
}
