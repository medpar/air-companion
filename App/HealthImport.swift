import Foundation
import HealthKit
import Combine

final class HealthImport: ObservableObject {
    @Published var busy = false
    @Published var message: String?
    private let health = HKHealthStore()
    private let resting = HKQuantityType(.restingHeartRate)
    private let variability = HKQuantityType(.heartRateVariabilitySDNN)
    private let sleep = HKCategoryType(.sleepAnalysis)
    func refresh(into library: AppStore) {
        guard !busy, !library.preview else { return }
        guard HKHealthStore.isHealthDataAvailable() else { message = "Apple Health is unavailable on this device."; return }
        busy = true; message = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await health.requestAuthorization(toShare: [], read: [resting, variability, sleep, HKObjectType.workoutType()])
                let start = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
                async let pulseSamples = samples(resting, since: start)
                async let hrvSamples = samples(variability, since: start)
                async let sleepSamples = samples(sleep, since: start)
                async let workoutSamples = samples(HKObjectType.workoutType(), since: start)
                let (pulse, hrv, nights, sessions) = try await (pulseSamples, hrvSamples, sleepSamples, workoutSamples)
                let metrics = quantityDays(pulse, kind: .restingPulse, unit: HKUnit.count().unitDivided(by: .minute()))
                    + quantityDays(hrv, kind: .hrvSDNN, unit: .secondUnit(with: .milli)) + sleepDays(nights)
                let workouts = sessions.compactMap { sample -> WorkoutEntry? in
                    guard let workout = sample as? HKWorkout, workout.duration > 0 else { return nil }
                    let name: String
                    switch workout.workoutActivityType {
                    case .running: name = "Run"
                    case .walking: name = "Walk"
                    case .cycling: name = "Ride"
                    case .swimming: name = "Swim"
                    case .traditionalStrengthTraining, .functionalStrengthTraining: name = "Strength"
                    case .yoga: name = "Yoga"
                    default: name = "Workout"
                    }
                    return WorkoutEntry(id: workout.uuid, date: workout.startDate, activity: name, minutes: workout.duration / 60, effort: nil, note: "", source: workout.sourceRevision.source.name)
                }
                guard !metrics.isEmpty || !workouts.isEmpty else {
                    message = "No readable samples. Previous history was kept. Health does not reveal whether access was denied or no data exists; check permissions in the Health app."
                    return
                }
                let importedKinds = Set(metrics.map(\.kind))
                let saved = library.change { data in
                    // Replace this bounded import window. Never merge different sources.
                    data.metrics.removeAll { $0.sourceID != "air" && importedKinds.contains($0.kind) }
                    data.metrics += metrics
                    let existing = Dictionary(uniqueKeysWithValues: data.workouts.map { ($0.id, $0) })
                    let importedIDs = Set(workouts.map(\.id))
                    data.workouts.removeAll { importedIDs.contains($0.id) }
                    data.workouts += workouts.map { workout in
                        var entry = workout
                        if let old = existing[entry.id] { entry.effort = old.effort; entry.note = old.note }
                        return entry
                    }
                    data.healthReadAt = Date()
                }
                if saved { message = "Apple Health updated. Choose a source for each trend. Empty metric types keep their previous history." }
            } catch { message = "Apple Health import did not finish. Your saved history is unchanged." }
        }
    }
    private func samples(_ type: HKSampleType, since start: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate), limit: 20001, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else if (samples?.count ?? 0) > 20000 { continuation.resume(throwing: CocoaError(.fileReadTooLarge)) }
                else { continuation.resume(returning: samples ?? []) }
            }
            health.execute(query)
        }
    }
    private func sourceID(_ sample: HKSample) -> String {
        // Keep devices separate even when the writing app is the same.
        sample.sourceRevision.source.bundleIdentifier + ":" + (sample.device?.localIdentifier ?? sample.device?.name ?? "default")
    }
    private func sourceName(_ sample: HKSample) -> String {
        sample.sourceRevision.source.name + (sample.device?.name.map { " · \($0)" } ?? "")
    }
    private func quantityDays(_ samples: [HKSample], kind: MetricKind, unit: HKUnit) -> [DailyMetric] {
        let groups = Dictionary(grouping: samples.compactMap { $0 as? HKQuantitySample }) {
            sourceID($0) + ":" + String(Calendar.current.startOfDay(for: $0.startDate).timeIntervalSince1970)
        }
        return groups.values.compactMap { group in
            guard let first = group.first, let mean = FitnessMath.mean(group.map { $0.quantity.doubleValue(for: unit) }.filter { $0 > 0 }) else { return nil }
            return DailyMetric(kind: kind, date: Calendar.current.startOfDay(for: first.startDate), value: mean, sourceID: sourceID(first), sourceName: sourceName(first))
        }
    }
    private func sleepDays(_ samples: [HKSample]) -> [DailyMetric] {
        let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let groups = Dictionary(grouping: samples.compactMap { $0 as? HKCategorySample }.filter { asleep.contains($0.value) }, by: { sourceID($0) })
        return groups.values.flatMap { group -> [DailyMetric] in
            guard let sample = group.first else { return [] }
            let intervals = group.filter { $0.endDate > $0.startDate }.map { DateInterval(start: $0.startDate, end: $0.endDate) }
            return FitnessMath.sleepByMorning(intervals).map { date, duration in
                DailyMetric(kind: .sleepHours, date: date, value: duration / 3600, sourceID: sourceID(sample), sourceName: sourceName(sample))
            }
        }
    }
}
