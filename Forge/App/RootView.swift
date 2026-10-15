import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case today, plan, exercises, progress, body
}

struct RootView: View {
    @Environment(WorkoutManager.self) private var workout
    @Environment(ExerciseLibrary.self) private var library
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(DataVersion.self) private var dataVersion
    @Environment(HistoryStore.self) private var history
    @AppStorage(SettingsKey.oneRepMaxFormula) private var formulaRaw = OneRepMaxFormula.brzycki.rawValue
    @Query private var customExercises: [CustomExercise]
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false
    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearanceSetting.system.rawValue
    @AppStorage(SettingsKey.weeklyGoal) private var weeklyGoal = SettingsDefaults.weeklyGoal
    @AppStorage(SettingsKey.bodyModel) private var bodyModelRaw = BodyModel.male.rawValue
    @State private var selectedTab: AppTab = .today

    var body: some View {
        @Bindable var workout = workout
        tabs
            .tabViewBottomAccessory(isEnabled: workout.activeSession != nil) {
                ActiveWorkoutAccessory()
            }
            .tint(Theme.ember)
            .fullScreenCover(isPresented: $workout.isPresented) {
                ActiveWorkoutView()
            }
            .sheet(item: $workout.finishedSession) { session in
                WorkoutSummaryView(session: session)
            }
            .overlay {
                if !hasOnboarded {
                    WelcomeView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: hasOnboarded)
            .preferredColorScheme(AppearanceSetting(rawValue: appearanceRaw)?.colorScheme)
            .onChange(of: customFingerprint, initial: true) {
                library.update(custom: customExercises)
            }
            .task(id: "\(dataVersion.value)|\(formulaRaw)|\(workout.activeSession == nil)") {
                // History only changes when a workout finishes, so skip rebuilds mid-workout.
                if workout.activeSession == nil || !history.hasLoaded {
                    history.rebuild(context: context)
                    WidgetSync.update(history: history.snapshot, context: context, library: library)
                }
            }
            .onChange(of: "\(weeklyGoal)|\(bodyModelRaw)") {
                WidgetSync.update(history: history.snapshot, context: context, library: library)
            }
            .onOpenURL { url in
                // Widgets link to forge://today.
                if url.scheme == WidgetShared.todayURL.scheme, url.host() == WidgetShared.todayURL.host() {
                    selectedTab = .today
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await HealthKitManager.shared.importBodyWeights(context: context, since: Calendar.current.date(byAdding: .day, value: -30, to: .now)) }
                }
            }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "flame.fill", value: AppTab.today) {
                TodayView(selectedTab: $selectedTab)
            }
            Tab("Plan", systemImage: "calendar", value: AppTab.plan) {
                SplitsView()
            }
            Tab("Exercises", systemImage: "dumbbell.fill", value: AppTab.exercises) {
                ExerciseLibraryView()
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                ProgressDashboardView()
            }
            Tab("Body", systemImage: "scalemass.fill", value: AppTab.body) {
                BodyView()
            }
        }
    }

    private var customFingerprint: [String] {
        customExercises.map { "\($0.id)|\($0.name)|\($0.primaryMusclesRaw)|\($0.secondaryMusclesRaw)|\($0.equipmentRaw)|\($0.trackingRaw)" }
    }
}
