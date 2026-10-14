import Foundation
@main struct StoreTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(directory: directory)
        precondition(store.change { $0.goal = 8000 })
        let original = try Data(contentsOf: directory.appendingPathComponent("air-library.json"))
        store.setPreview(true)
        precondition(store.change { $0.goal = 15000; $0.workouts.removeAll() })
        let afterPreview = try Data(contentsOf: directory.appendingPathComponent("air-library.json"))
        precondition(afterPreview == original)
        store.setPreview(false); precondition(store.data.goal == 8000)
        let recovered = AppStore(directory: directory); precondition(recovered.data.goal == 8000)
        let start = Date(timeIntervalSince1970: 1000)
        var session = WorkoutSession(now: start)
        session.pause(at: start.addingTimeInterval(600))
        precondition(session.elapsed(at: start.addingTimeInterval(1000)) == 600)
        session.resume(at: start.addingTimeInterval(1000))
        precondition(session.elapsed(at: start.addingTimeInterval(1300)) == 900)
        precondition(recovered.change { $0.session = session })
        let restored = AppStore(directory: directory)
        precondition(restored.data.session?.elapsed(at: start.addingTimeInterval(1300)) == 900)
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: directory.appendingPathComponent("air-library.json"))
        let invalid = AppStore(directory: directory)
        precondition(invalid.error != nil && !invalid.change { $0.goal = 3000 })
        let unchanged = try Data(contentsOf: directory.appendingPathComponent("air-library.json"))
        precondition(unchanged == corrupt)
        print("PASS: protected persistence, preview isolation, relaunch recovery, timer pauses and corrupt-file preservation")
    }
}
