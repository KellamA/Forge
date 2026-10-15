import SwiftData
import SwiftUI

@main
struct ForgeApp: App {
    let container: ModelContainer
    @State private var workoutManager: WorkoutManager
    @State private var library: ExerciseLibrary
    @State private var dataVersion = DataVersion()
    @State private var history = HistoryStore()

    init() {
        SettingsDefaults.register()
        let container = ModelContainerFactory.make()
        self.container = container
        let library = ExerciseLibrary()
        _library = State(initialValue: library)
        _workoutManager = State(initialValue: WorkoutManager(context: container.mainContext, library: library))
        HealthKitManager.context = container.mainContext
        // Warm the catalog and body map off the first frame.
        DispatchQueue.global(qos: .userInitiated).async {
            _ = ExerciseCatalog.shared.all.count
            _ = BodyMapStore.shared
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(workoutManager)
                .environment(library)
                .environment(dataVersion)
                .environment(history)
                .task { await DemoData.seedIfRequested(context: container.mainContext) }
        }
        .modelContainer(container)
    }
}

enum ModelContainerFactory {
    static func make() -> ModelContainer {
        let schema = Schema(ForgeSchema.models)
        let arguments = ProcessInfo.processInfo.arguments
        // The default store lives in Application Support, which doesn't exist on a fresh install.
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        if arguments.contains("-inMemoryStore") {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: config)
        }
        do {
            // Syncs to the iCloud private database when the app is signed with the CloudKit entitlement.
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            print("CloudKit-backed store unavailable (\(error)); falling back to a local store.")
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: config)
        }
    }
}

/// Bumped whenever SwiftData saves, so value-type analytics snapshots know to rebuild.
@MainActor
@Observable
final class DataVersion {
    private(set) var value = 0
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.value += 1 }
        }
    }

    func bump() { value += 1 }
}
