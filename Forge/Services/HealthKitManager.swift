import Foundation
import HealthKit
import SwiftData

/// Apple Health sync: imports weigh-ins, exports weigh-ins, strength workouts and runs.
@MainActor
@Observable
final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()
    private(set) var lastError: String?
    private(set) var isImporting = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var bodyMass: HKQuantityType { HKQuantityType(.bodyMass) }
    private var bodyFat: HKQuantityType { HKQuantityType(.bodyFatPercentage) }
    private var energy: HKQuantityType { HKQuantityType(.activeEnergyBurned) }
    private var distance: HKQuantityType { HKQuantityType(.distanceWalkingRunning) }

    var isConnected: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.healthConnected)
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else {
            lastError = "Apple Health isn't available on this device."
            return false
        }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), bodyMass, bodyFat, energy, distance]
        let read: Set<HKObjectType> = [bodyMass, bodyFat, HKObjectType.workoutType()]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            UserDefaults.standard.set(true, forKey: SettingsKey.healthConnected)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Body weight import

    /// Imports weigh-ins from Health that aren't already in the app. Returns the number imported.
    @discardableResult
    func importBodyWeights(context: ModelContext, since: Date? = nil) async -> Int {
        guard isAvailable, isConnected, UserDefaults.standard.bool(forKey: SettingsKey.healthImportWeight) else { return 0 }
        isImporting = true
        defer { isImporting = false }
        let start = since ?? Calendar.current.date(byAdding: .year, value: -3, to: .now)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMass, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return 0 }

        let existing = (try? context.fetch(FetchDescriptor<BodyWeightEntry>())) ?? []
        let knownUUIDs = Set(existing.map(\.healthKitUUID).filter { !$0.isEmpty })
        let ownBundle = Bundle.main.bundleIdentifier ?? ""
        var imported = 0
        for sample in samples {
            if sample.sourceRevision.source.bundleIdentifier == ownBundle { continue }
            let uuid = sample.uuid.uuidString
            if knownUUIDs.contains(uuid) { continue }
            let pounds = sample.quantity.doubleValue(for: .pound())
            // Skip near-duplicates of manual entries (same weight within 10 minutes).
            let duplicate = existing.contains {
                abs($0.date.timeIntervalSince(sample.startDate)) < 600 && abs($0.weight - pounds) < 0.15
            }
            if duplicate { continue }
            let entry = BodyWeightEntry(weight: (pounds * 10).rounded() / 10, date: sample.startDate)
            entry.healthKitUUID = uuid
            context.insert(entry)
            imported += 1
        }
        if imported > 0 { try? context.save() }
        return imported
    }

    // MARK: - Export

    func save(weightEntry entry: BodyWeightEntry) async {
        guard isAvailable, isConnected, entry.healthKitUUID.isEmpty,
              UserDefaults.standard.bool(forKey: SettingsKey.healthSaveWeight) else { return }
        var samples: [HKSample] = [
            HKQuantitySample(type: bodyMass, quantity: HKQuantity(unit: .pound(), doubleValue: entry.weight),
                             start: entry.date, end: entry.date),
        ]
        if entry.bodyFat > 0 {
            samples.append(HKQuantitySample(type: bodyFat, quantity: HKQuantity(unit: .percent(), doubleValue: entry.bodyFat / 100),
                                            start: entry.date, end: entry.date))
        }
        do {
            try await store.save(samples)
            entry.savedToHealth = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func save(workout session: WorkoutSession) async {
        guard isAvailable, isConnected, !session.savedToHealth, let end = session.endedAt else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        // Strength training ≈ 5 METs: kcal = METs × kg × hours.
        let kcal = 5.0 * latestWeightKg() * (end.timeIntervalSince(session.startedAt) / 3600)
        do {
            try await builder.beginCollection(at: session.startedAt)
            let sample = HKQuantitySample(type: energy, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                          start: session.startedAt, end: end)
            try await builder.addSamples([sample])
            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "Forge"])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            session.savedToHealth = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func save(cardio log: CardioLog) async {
        guard isAvailable, isConnected, !log.savedToHealth, log.distance > 0,
              UserDefaults.standard.bool(forKey: SettingsKey.healthSaveWorkouts) else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = log.type == .outdoor ? .outdoor : .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        let duration = log.durationSeconds > 0 ? log.durationSeconds : log.distance * 9 * 60
        let start = log.date.addingTimeInterval(-duration)
        let end = log.date
        // Rule of thumb: ~0.63 kcal per lb of body weight per mile.
        let kcal = 0.63 * latestWeightKg() * 2.20462 * log.distance
        do {
            try await builder.beginCollection(at: start)
            try await builder.addSamples([
                HKQuantitySample(type: distance, quantity: HKQuantity(unit: .mile(), doubleValue: log.distance), start: start, end: end),
                HKQuantitySample(type: energy, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal), start: start, end: end),
            ])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            log.savedToHealth = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Latest logged body weight in kg (defaults to 80 kg).
    private func latestWeightKg() -> Double {
        var descriptor = FetchDescriptor<BodyWeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        if let context = HealthKitManager.context, let entry = try? context.fetch(descriptor).first, entry.weight > 0 {
            return entry.weight / 2.20462
        }
        return 80
    }

    /// Set at launch so the manager can read the latest body weight.
    static var context: ModelContext?
}
