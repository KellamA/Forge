import ActivityKit
import SwiftData
import SwiftUI
import UserNotifications

/// A previous set, shown in the "Previous" column while logging.
struct SetSnapshot: Hashable {
    let weight: Double
    let reps: Int
    let seconds: Int
    let isWarmup: Bool
}

/// Owns the in-progress workout: creating it from a plan, logging sets, rest timing,
/// PR detection, the Live Activity, and finishing.
@MainActor
@Observable
final class WorkoutManager {
    let context: ModelContext
    let library: ExerciseLibrary

    private(set) var activeSession: WorkoutSession?
    var isPresented = false
    /// Set after finishing, to present the summary.
    var finishedSession: WorkoutSession?

    // Rest timer
    private(set) var restEndsAt: Date?
    private(set) var restTotal: TimeInterval = 0
    private(set) var restLabel = ""
    /// Incremented when a rest period ends in the foreground (drives haptics).
    private(set) var restFinishedTick = 0

    // PRs
    private(set) var prTick = 0
    private(set) var latestPRMessage: String?

    @ObservationIgnored private var restTask: Task<Void, Never>?
    @ObservationIgnored private var activity: Activity<WorkoutActivityAttributes>?
    @ObservationIgnored private var baselines: [String: Double] = [:]
    @ObservationIgnored private(set) var previousSets: [String: [SetSnapshot]] = [:]
    @ObservationIgnored private(set) var hints: [String: String] = [:]

    init(context: ModelContext, library: ExerciseLibrary) {
        self.context = context
        self.library = library
        restoreState()
    }

    // MARK: - Lifecycle

    private func restoreState() {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        activeSession = try? context.fetch(descriptor).first
        let existing = Activity<WorkoutActivityAttributes>.activities
        if let session = activeSession {
            prepareContext(for: session.orderedExercises)
            activity = existing.first
            if let end = UserDefaults.standard.object(forKey: SettingsKey.restTimerEnd) as? Date, end > .now {
                restEndsAt = end
                restTotal = UserDefaults.standard.double(forKey: SettingsKey.restTimerTotal)
                scheduleRestCompletion()
            }
            if activity == nil { startActivity() } else { updateActivity() }
        } else {
            for stale in existing {
                Task { await stale.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }

    /// Starts a workout from a split day, or an empty workout when `day` is nil.
    func start(day: SplitDay? = nil, name: String? = nil) {
        if activeSession != nil {
            isPresented = true
            return
        }
        let session = WorkoutSession(name: name ?? day?.displayName ?? Self.defaultName())
        context.insert(session)
        session.splitID = day?.split?.id
        session.splitDayID = day?.id

        if let day {
            for (index, planned) in day.orderedExercises.enumerated() {
                let info = library.exercise(id: planned.exerciseID)
                    ?? .placeholder(id: planned.exerciseID, name: planned.exerciseName)
                let ex = SessionExercise(exercise: info, order: index)
                context.insert(ex)
                ex.session = session
                ex.targetSets = planned.targetSets
                ex.repLow = planned.repLow
                ex.repHigh = planned.repHigh
                ex.targetSeconds = planned.targetSeconds
                ex.restSeconds = planned.restSeconds
                ex.notes = planned.notes
            }
        }
        activeSession = session
        prepareContext(for: session.orderedExercises)
        for ex in session.orderedExercises { createInitialSets(for: ex) }
        save()
        requestNotificationPermission()
        startActivity()
        withAnimation(.snappy) { isPresented = true }
    }

    private static func defaultName() -> String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 4..<12: return "Morning Workout"
        case 12..<17: return "Afternoon Workout"
        default: return "Evening Workout"
        }
    }

    /// Finishes the active workout. Unfinished sets are dropped. Returns false if nothing was logged.
    @discardableResult
    func finish() -> Bool {
        guard let session = activeSession else { return false }
        for ex in session.orderedExercises {
            for set in ex.orderedSets where !set.isCompleted {
                context.delete(set)
            }
            if ex.completedSets.isEmpty { context.delete(ex) }
        }
        let hasWork = !(session.exercises ?? []).filter { !$0.completedSets.isEmpty }.isEmpty || !(session.cardio ?? []).isEmpty
        guard hasWork else {
            discard()
            return false
        }
        session.endedAt = .now
        SplitService.recordCompletion(splitID: session.splitID, dayID: session.splitDayID, at: .now, context: context)
        save()
        endRest()
        endActivity()
        activeSession = nil
        isPresented = false
        finishedSession = session
        if UserDefaults.standard.bool(forKey: SettingsKey.healthSaveWorkouts) {
            Task { await HealthKitManager.shared.save(workout: session) }
        }
        return true
    }

    func discard() {
        guard let session = activeSession else { return }
        context.delete(session)
        save()
        endRest()
        endActivity()
        activeSession = nil
        isPresented = false
    }

    // MARK: - Exercises

    func addExercises(_ infos: [ExerciseInfo]) {
        guard let session = activeSession else { return }
        var order = (session.exercises ?? []).map(\.order).max().map { $0 + 1 } ?? 0
        var added: [SessionExercise] = []
        for info in infos {
            let ex = SessionExercise(exercise: info, order: order)
            context.insert(ex)
            ex.session = session
            order += 1
            added.append(ex)
        }
        prepareContext(for: added)
        for ex in added { createInitialSets(for: ex) }
        save()
        updateActivity()
    }

    func replace(_ exercise: SessionExercise, with info: ExerciseInfo) {
        guard let session = activeSession else { return }
        let order = exercise.order
        let ex = SessionExercise(exercise: info, order: order)
        context.insert(ex)
        ex.session = session
        ex.targetSets = exercise.targetSets
        ex.restSeconds = exercise.restSeconds
        context.delete(exercise)
        prepareContext(for: [ex])
        createInitialSets(for: ex)
        save()
        updateActivity()
    }

    func remove(_ exercise: SessionExercise) {
        context.delete(exercise)
        if let session = activeSession {
            for (i, ex) in session.orderedExercises.filter({ $0.id != exercise.id }).enumerated() { ex.order = i }
        }
        save()
        updateActivity()
    }

    func move(_ exercises: [SessionExercise]) {
        for (i, ex) in exercises.enumerated() { ex.order = i }
        save()
        updateActivity()
    }

    // MARK: - Sets

    func addSet(to exercise: SessionExercise) {
        let sets = exercise.orderedSets
        let last = sets.last
        let set = SetLog(order: (sets.map(\.order).max() ?? -1) + 1,
                         weight: last?.weight ?? 0,
                         reps: last?.reps ?? exercise.repLow,
                         seconds: last?.seconds ?? exercise.targetSeconds)
        context.insert(set)
        set.exercise = exercise
        save()
        updateActivity()
    }

    func delete(_ set: SetLog) {
        guard let exercise = set.exercise else { return }
        context.delete(set)
        for (i, s) in exercise.orderedSets.filter({ $0.id != set.id }).enumerated() { s.order = i }
        PRService.evaluate(exercise, baseline: baselines[exercise.exerciseID])
        save()
        updateActivity()
    }

    func toggleWarmup(_ set: SetLog) {
        set.isWarmup.toggle()
        if let ex = set.exercise { PRService.evaluate(ex, baseline: baselines[ex.exerciseID]) }
        save()
    }

    func toggleComplete(_ set: SetLog) {
        guard let exercise = set.exercise else { return }
        if set.isCompleted {
            set.isCompleted = false
            set.completedAt = nil
            PRService.evaluate(exercise, baseline: baselines[exercise.exerciseID])
            save()
            updateActivity()
            return
        }
        switch exercise.tracking {
        case .weightReps, .bodyweight:
            if set.reps == 0 { set.reps = exercise.repLow }
        case .duration:
            if set.seconds == 0 { set.seconds = exercise.targetSeconds }
        }
        set.isCompleted = true
        set.completedAt = .now
        if PRService.evaluate(exercise, baseline: baselines[exercise.exerciseID]) {
            latestPRMessage = "New PR · \(exercise.exerciseName)"
            prTick += 1
        }
        if UserDefaults.standard.bool(forKey: SettingsKey.autoStartRest), !set.isWarmup || exercise.restSeconds > 0,
           hasRemainingSets() {
            let label = nextSetDescription(after: exercise) ?? exercise.exerciseName
            startRest(seconds: set.isWarmup ? min(60, exercise.restSeconds) : exercise.restSeconds, label: label)
        }
        save()
        updateActivity()
    }

    private func hasRemainingSets() -> Bool {
        guard let session = activeSession else { return false }
        return session.orderedExercises.contains { $0.orderedSets.contains { !$0.isCompleted } }
    }

    /// Seeds set rows from the last time this exercise was performed.
    private func createInitialSets(for exercise: SessionExercise) {
        let previous = (previousSets[exercise.exerciseID] ?? []).filter { !$0.isWarmup }
        let increment = UserDefaults.standard.double(forKey: SettingsKey.weightIncrement)
        let progress = shouldProgress(exercise, previous: previous)
        for i in 0..<max(1, exercise.targetSets) {
            let prev = i < previous.count ? previous[i] : previous.last
            let set = SetLog(order: i)
            switch exercise.tracking {
            case .weightReps:
                if progress, let top = previous.map(\.weight).max() {
                    set.weight = top + increment
                    set.reps = exercise.repLow
                } else {
                    set.weight = prev?.weight ?? 0
                    set.reps = prev?.reps ?? exercise.repLow
                }
            case .bodyweight:
                set.weight = prev?.weight ?? 0
                set.reps = prev?.reps ?? exercise.repLow
            case .duration:
                set.seconds = prev?.seconds ?? exercise.targetSeconds
            }
            context.insert(set)
            set.exercise = exercise
        }
    }

    private func shouldProgress(_ exercise: SessionExercise, previous: [SetSnapshot]) -> Bool {
        guard exercise.tracking == .weightReps, !previous.isEmpty, exercise.repHigh > 0 else { return false }
        return previous.allSatisfy { $0.reps >= exercise.repHigh && $0.weight > 0 }
    }

    /// Loads previous performance, progression hints and PR baselines for exercises.
    private func prepareContext(for exercises: [SessionExercise]) {
        let increment = UserDefaults.standard.double(forKey: SettingsKey.weightIncrement)
        for ex in exercises {
            let id = ex.exerciseID
            let last = lastPerformance(exerciseID: id)
            let snapshots = last?.orderedSets.filter(\.isCompleted).map {
                SetSnapshot(weight: $0.weight, reps: $0.reps, seconds: $0.seconds, isWarmup: $0.isWarmup)
            } ?? []
            previousSets[id] = snapshots
            let working = snapshots.filter { !$0.isWarmup }
            if shouldProgress(ex, previous: working), let top = working.map(\.weight).max() {
                hints[id] = "You hit \(ex.repHigh)+ reps on every set last time. Go up to \(Fmt.weight(top + increment)) lb."
            } else {
                hints[id] = nil
            }
            baselines[id] = PRService.baseline(exerciseID: id, tracking: ex.tracking, excluding: activeSession?.id, context: context)
        }
    }

    func lastPerformance(exerciseID: String) -> SessionExercise? {
        let descriptor = FetchDescriptor<SessionExercise>(predicate: #Predicate { $0.exerciseID == exerciseID })
        let entries = (try? context.fetch(descriptor)) ?? []
        return entries
            .filter { $0.session?.endedAt != nil && $0.session?.id != activeSession?.id && !$0.completedSets.isEmpty }
            .max { ($0.session?.startedAt ?? .distantPast) < ($1.session?.startedAt ?? .distantPast) }
    }

    func previous(for exercise: SessionExercise) -> [SetSnapshot] {
        previousSets[exercise.exerciseID] ?? []
    }

    func hint(for exercise: SessionExercise) -> String? {
        hints[exercise.exerciseID]
    }

    // MARK: - Rest timer

    func startRest(seconds: Int, label: String) {
        guard seconds > 0 else { return }
        restTotal = TimeInterval(seconds)
        restEndsAt = Date.now.addingTimeInterval(TimeInterval(seconds))
        restLabel = label
        persistRest()
        scheduleRestCompletion()
        updateActivity()
    }

    func adjustRest(by delta: TimeInterval) {
        guard let end = restEndsAt else { return }
        let newEnd = end.addingTimeInterval(delta)
        if newEnd <= .now {
            endRest()
            updateActivity()
            return
        }
        restEndsAt = newEnd
        restTotal = max(1, restTotal + delta)
        persistRest()
        scheduleRestCompletion()
        updateActivity()
    }

    func skipRest() {
        endRest()
        updateActivity()
    }

    private func endRest() {
        restTask?.cancel()
        restTask = nil
        restEndsAt = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest-timer"])
        UserDefaults.standard.removeObject(forKey: SettingsKey.restTimerEnd)
    }

    private func persistRest() {
        UserDefaults.standard.set(restEndsAt, forKey: SettingsKey.restTimerEnd)
        UserDefaults.standard.set(restTotal, forKey: SettingsKey.restTimerTotal)
    }

    private func scheduleRestCompletion() {
        restTask?.cancel()
        guard let end = restEndsAt else { return }
        let delay = max(0, end.timeIntervalSinceNow)
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.restDidFinish()
        }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["rest-timer"])
        let content = UNMutableNotificationContent()
        content.title = "Rest's up"
        content.body = restLabel.isEmpty ? "Time for your next set." : "Next: \(restLabel)"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        center.add(UNNotificationRequest(identifier: "rest-timer", content: content, trigger: trigger))
    }

    private func restDidFinish() {
        guard let end = restEndsAt, end.timeIntervalSinceNow < 0.5 else { return }
        restEndsAt = nil
        UserDefaults.standard.removeObject(forKey: SettingsKey.restTimerEnd)
        restFinishedTick += 1
        updateActivity()
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Live Activity

    private func nextSet() -> (SessionExercise, SetLog, Int)? {
        guard let session = activeSession else { return nil }
        for ex in session.orderedExercises {
            let sets = ex.orderedSets
            if let index = sets.firstIndex(where: { !$0.isCompleted }) {
                return (ex, sets[index], index)
            }
        }
        return nil
    }

    /// Short label for the rest timer: "Set 2 · 230 × 8", or the exercise name when moving on.
    private func nextSetDescription(after current: SessionExercise? = nil) -> String? {
        guard let (ex, set, index) = nextSet() else { return nil }
        if ex.id == current?.id {
            return "Set \(index + 1) · \(describe(set, tracking: ex.tracking).replacingOccurrences(of: " lb", with: ""))"
        }
        return ex.exerciseName
    }

    /// Live caption under the rest countdown. Reads current set values, so edits made while resting show up.
    var restCaption: String {
        guard let (ex, set, index) = nextSet() else { return "Last set done" }
        if ex.completedSets.isEmpty {
            return "Next: \(ex.exerciseName)"
        }
        return "Set \(index + 1) · \(describe(set, tracking: ex.tracking).replacingOccurrences(of: " lb", with: ""))"
    }

    private func describe(_ set: SetLog, tracking: TrackingType) -> String {
        switch tracking {
        case .weightReps: return "\(Fmt.weight(set.weight)) lb × \(set.reps)"
        case .bodyweight: return set.weight > 0 ? "+\(Fmt.weight(set.weight)) lb × \(set.reps)" : "\(set.reps) reps"
        case .duration: return "\(set.seconds)s"
        }
    }

    private func activityState() -> WorkoutActivityAttributes.ContentState {
        let session = activeSession
        let all = session?.orderedExercises.flatMap(\.orderedSets) ?? []
        let completed = all.filter(\.isCompleted).count
        if let (ex, set, index) = nextSet() {
            return .init(exerciseName: ex.exerciseName,
                         setLabel: "Set \(index + 1) of \(ex.orderedSets.count)",
                         detail: describe(set, tracking: ex.tracking),
                         restEndsAt: restEndsAt, restTotal: restTotal,
                         completedSets: completed, totalSets: all.count)
        }
        return .init(exerciseName: all.isEmpty ? "Add an exercise" : "All sets complete",
                     setLabel: all.isEmpty ? "" : "Finish when you're ready",
                     detail: "", restEndsAt: restEndsAt, restTotal: restTotal,
                     completedSets: completed, totalSets: all.count)
    }

    private func startActivity() {
        guard let session = activeSession, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WorkoutActivityAttributes(workoutName: session.name, startedAt: session.startedAt)
        activity = try? Activity.request(attributes: attributes,
                                         content: .init(state: activityState(), staleDate: nil),
                                         pushType: nil)
    }

    /// Pushes edited set values to the Live Activity. Called when a set field loses focus.
    func refreshLiveActivity() {
        updateActivity()
    }

    private func updateActivity() {
        guard let activity else { return }
        let content = ActivityContent(state: activityState(), staleDate: nil)
        Task { await activity.update(content) }
    }

    private func endActivity() {
        guard let activity else { return }
        let content = ActivityContent(state: activityState(), staleDate: nil)
        Task { await activity.end(content, dismissalPolicy: .immediate) }
        self.activity = nil
    }

    // MARK: - Persistence

    func save() {
        do {
            try context.save()
        } catch {
            print("Save failed: \(error)")
        }
    }
}
