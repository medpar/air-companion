import Foundation
import Combine

struct SavedData: Codable {
    var schema = 1
    var workouts: [WorkoutEntry] = []
    var metrics: [DailyMetric] = []
    var rules: [AutomationRule] = []
    var receipts: [RuleReceipt] = []
    var sources: [String: String] = [:]
    var goal = 10000
    var healthReadAt: Date?
    var session: WorkoutSession?
}
final class AppStore: ObservableObject {
    @Published private(set) var data = SavedData()
    @Published var error: String?
    @Published var preview = false
    private var realData: SavedData?
    private let url: URL
    init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = directory.appendingPathComponent("air-library.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let saved = try JSONDecoder().decode(SavedData.self, from: Data(contentsOf: url))
                guard saved.schema == 1 else { throw CocoaError(.coderReadCorrupt) }
                data = saved
            }
        } catch { self.error = "Your saved library could not be opened. It has not been overwritten."; loadFailed = true }
    }
    private var loadFailed = false
    @discardableResult func change(_ body: (inout SavedData) -> Void) -> Bool {
        guard !loadFailed || preview else { return false }
        var next = data; body(&next)
        do {
            if !preview { try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtection]) }
            data = next; return true
        } catch { self.error = "Couldn’t save your changes. Check available iPhone storage."; return false }
    }
    func setPreview(_ enabled: Bool) {
        guard preview != enabled else { return }
        if enabled { realData = data; data = Self.examples(); preview = true }
        else { data = realData ?? SavedData(); realData = nil; preview = false }
    }
    func points(_ kind: MetricKind) -> [DailyMetric] {
        let candidates = data.metrics.filter { $0.kind == kind }
        let preferred = data.sources[kind.rawValue]
        let source = candidates.contains(where: { $0.sourceID == preferred }) ? preferred : candidates.sorted { $0.sourceName < $1.sourceName }.first?.sourceID
        return candidates.filter { $0.sourceID == source }.sorted { $0.date < $1.date }
    }
    static func examples(now: Date = Date()) -> SavedData {
        var data = SavedData(); let cal = Calendar.current
        for offset in 1...42 {
            let date = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: now))!
            for kind in MetricKind.allCases {
                let wave = sin(Double(offset) * 0.7)
                let value: Double
                switch kind { case .restingPulse: value = 57 + wave * 3; case .hrvSDNN: value = 49 + wave * 8; case .sleepHours: value = 7.4 + wave * 0.7; case .steps: value = 8400 + wave * 2700 }
                data.metrics.append(DailyMetric(kind: kind, date: date, value: value, sourceID: "example", sourceName: "Example data"))
            }
        }
        for offset in [1, 3, 5, 8, 10, 13, 15, 17] {
            data.workouts.append(WorkoutEntry(id: UUID(), date: cal.date(byAdding: .day, value: -offset, to: now)!, activity: offset % 2 == 0 ? "Strength" : "Run", minutes: Double(30 + offset), effort: 6, note: "", source: "Example data"))
        }
        data.rules = [AutomationRule()]; data.healthReadAt = now
        return data
    }
}
