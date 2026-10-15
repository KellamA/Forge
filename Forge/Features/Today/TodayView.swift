import SwiftData
import SwiftUI

struct TodayView: View {
    @Binding var selectedTab: AppTab

    @Environment(WorkoutManager.self) private var workout
    @Environment(HistoryStore.self) private var history
    @Environment(ExerciseLibrary.self) private var library
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WorkoutSplit> { $0.isActive }) private var activeSplits: [WorkoutSplit]
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var weights: [BodyWeightEntry]
    @AppStorage(SettingsKey.userName) private var userName = ""
    @AppStorage(SettingsKey.weeklyGoal) private var weeklyGoal = SettingsDefaults.weeklyGoal

    @State private var cardioPrefill: CardioPrefill?
    @State private var showingWeightEntry = false
    @State private var showingSettings = false
    @State private var showingTemplates = false
    @State private var now = Date()

    private var split: WorkoutSplit? { activeSplits.first }
    private var snapshot: HistorySnapshot { history.snapshot }

    var body: some View {
        let plan = SplitService.todayPlan(split: split, completions: snapshot.completions, now: now)
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if workout.activeSession != nil {
                        resumeCard
                    }
                    planSection(plan)
                    weeklyCard
                    statsRow
                    prsSection
                    recentSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Start Empty Workout", systemImage: "plus.circle") { workout.start() }
                        Button("Log a Run", systemImage: "figure.run") { cardioPrefill = CardioPrefill() }
                        Button("Log Body Weight", systemImage: "scalemass") { showingWeightEntry = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Quick Add")
                }
            }
            .navigationDestination(for: SessionLink.self) { link in
                SessionDetailView(sessionID: link.id)
            }
            .navigationDestination(for: HistoryLink.self) { _ in
                HistoryView()
            }
            .sheet(item: $cardioPrefill) { CardioLogView(prefill: $0) }
            .sheet(isPresented: $showingWeightEntry) { WeightEntryEditor(entry: nil) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingTemplates) {
                NavigationStack {
                    TemplateGallery { showingTemplates = false }
                }
            }
            .onAppear { now = .now }
            .refreshable { now = .now }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(greeting)
                .font(.largeTitle.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        let name = userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var resumeCard: some View {
        Button {
            workout.isPresented = true
        } label: {
            HStack(spacing: 14) {
                IconBadge(systemName: "play.fill", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout in progress")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ember)
                    Text(workout.activeSession?.name ?? "")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let start = workout.activeSession?.startedAt {
                        Text(start, style: .timer)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("Resume")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Theme.accentGradient, in: Capsule())
            }
            .cardStyle()
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Plan

    @ViewBuilder
    private func planSection(_ plan: TodayPlan) -> some View {
        if let split = plan.split {
            if split.orderedDays.isEmpty {
                EmptyStateCard(icon: "calendar.badge.plus", title: "\(split.name) has no days yet",
                               message: "Add workouts to your split to see what's up next here.",
                               actionTitle: "Open Plan") { selectedTab = .plan }
            } else if plan.isAllDoneToday || (!plan.completedToday.isEmpty && plan.days.isEmpty && !plan.isRestDay) {
                DoneTodayCard(completed: plan.completedToday, nextUp: plan.nextUp, nextDate: plan.nextUpDate,
                              sessionsToday: snapshot.sessions.filter { Calendar.current.isDateInToday($0.start) })
            } else if plan.isRestDay {
                RestDayCard(split: split, nextUp: plan.nextUp, nextDate: plan.nextUpDate) { day in
                    start(day, split: split)
                }
            } else {
                ForEach(plan.pendingDays.filter { $0.id != workout.activeSession?.splitDayID }) { day in
                    UpNextCard(day: day, split: split, library: library, isWeekly: split.scheduleMode == .weekly) {
                        start(day, split: split)
                    } onSkip: {
                        withAnimation(.snappy) {
                            SplitService.skip(in: split, current: day)
                            try? context.save()
                        }
                    } onPick: { other in
                        if split.scheduleMode == .rotation {
                            SplitService.setNext(other, in: split)
                            try? context.save()
                        } else {
                            start(other, split: split)
                        }
                    }
                }
            }
        } else {
            NoSplitCard {
                showingTemplates = true
            } onBuild: {
                selectedTab = .plan
            } onQuick: {
                workout.start()
            }
        }
    }

    private func start(_ day: SplitDay, split: WorkoutSplit) {
        if day.kind == .cardio {
            cardioPrefill = CardioPrefill(type: day.cardioType, distance: day.cardioDistance, splitID: split.id, dayID: day.id)
        } else {
            workout.start(day: day)
        }
    }

    // MARK: - Weekly

    private var weeklyCard: some View {
        let calendar = Calendar.current
        let weekStart = calendar.startOfWeek(for: now)
        let interval = DateInterval(start: weekStart, duration: 7 * 86400)
        let done = snapshot.trainingCount(in: interval)
        let streak = snapshot.weeklyStreak(goal: weeklyGoal)
        let trained = snapshot.trainedDays()
        return VStack(spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(progress: Double(done) / Double(max(1, weeklyGoal)), lineWidth: 9)
                    VStack(spacing: -2) {
                        Text("\(done)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .contentTransition(.numericText(value: Double(done)))
                        Text("of \(weeklyGoal)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 74, height: 74)
                VStack(alignment: .leading, spacing: 4) {
                    Text(done >= weeklyGoal ? "Weekly goal smashed" : "This week")
                        .font(.headline)
                    Text(done >= weeklyGoal ? "You've hit \(weeklyGoal) sessions. Anything else is a bonus." :
                            "\(weeklyGoal - done) more \(weeklyGoal - done == 1 ? "session" : "sessions") to hit your goal.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if streak > 0 {
                        Label("\(streak)-week streak", systemImage: "flame.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.ember)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { offset in
                    let day = calendar.date(byAdding: .day, value: offset, to: weekStart)!
                    let isToday = calendar.isDateInToday(day)
                    let didTrain = trained.contains(calendar.startOfDay(for: day))
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(isToday ? Theme.ember : .secondary)
                        ZStack {
                            Circle()
                                .fill(didTrain ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.subtleFill))
                            if didTrain {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(.white)
                            } else {
                                Text(day.formatted(.dateTime.day()))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(day > now ? .tertiary : .secondary)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(isToday ? Theme.ember : .clear, lineWidth: 2).padding(-3))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Stats

    private var statsRow: some View {
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        let weekStart = Calendar.current.startOfWeek(for: now)
        let weekVolume = snapshot.sessions(since: weekStart).reduce(0) { $0 + $1.volume }
        let latest = weights.first
        let past = weights.first { $0.date <= monthAgo }
        return HStack(spacing: 12) {
            Button {
                selectedTab = .body
            } label: {
                StatTile(title: "Body Weight",
                         value: latest.map { Fmt.weight($0.weight) } ?? "–",
                         unit: latest == nil ? nil : "lb",
                         icon: "scalemass.fill", tint: Theme.body,
                         footnote: deltaText(latest: latest?.weight, past: past?.weight))
            }
            .buttonStyle(PressableStyle())
            Button {
                selectedTab = .progress
            } label: {
                StatTile(title: "Volume This Week", value: Fmt.volume(weekVolume), unit: "lb",
                         icon: "chart.bar.fill", tint: Theme.ember,
                         footnote: "\(snapshot.sessions(since: weekStart).count) workouts")
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func deltaText(latest: Double?, past: Double?) -> String {
        guard let latest else { return "Tap to log" }
        guard let past else { return "Latest weigh-in" }
        return "\(Fmt.signed(latest - past)) lb in 30 days"
    }

    // MARK: - PRs

    @ViewBuilder
    private var prsSection: some View {
        let prs = snapshot.recentPRs(limit: 8)
        if !prs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Recent PRs")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(prs) { pr in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "trophy.fill")
                                        .foregroundStyle(Theme.gold)
                                    Spacer()
                                    Text(Fmt.relativeDay(pr.date))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Text(pr.exerciseName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2, reservesSpace: true)
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(Fmt.weight(pr.value.rounded()))
                                        .font(.title3.weight(.bold).monospacedDigit())
                                        .foregroundStyle(Theme.accentGradient)
                                    Text(pr.unit == "lb" ? "lb e1RM" : pr.unit)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Text(pr.unit == "lb" ? pr.detail : " ")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 150, alignment: .leading)
                            .cardStyle(padding: 14)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
            }
        }
    }

    // MARK: - Recent

    @ViewBuilder
    private var recentSection: some View {
        let recent = Array(snapshot.sessions.prefix(3))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Recent Workouts") {
                    NavigationLink("See All", value: HistoryLink())
                        .foregroundStyle(Theme.ember)
                }
                VStack(spacing: 10) {
                    ForEach(recent) { session in
                        NavigationLink(value: SessionLink(id: session.modelID)) {
                            SessionSummaryRow(session: session)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }
}

struct SessionLink: Hashable {
    let id: PersistentIdentifier
}

struct HistoryLink: Hashable {}

// MARK: - Plan cards

private struct UpNextCard: View {
    let day: SplitDay
    let split: WorkoutSplit
    let library: ExerciseLibrary
    let isWeekly: Bool
    var onStart: () -> Void
    var onSkip: () -> Void
    var onPick: (SplitDay) -> Void

    var body: some View {
        let exercises = day.orderedExercises
        let isCardio = day.kind == .cardio
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isWeekly ? "TODAY" : "UP NEXT")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(day.displayName)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                if !isCardio && !exercises.isEmpty {
                    BodyMapView(intensities: day.muscleIntensities(in: library), tint: .white, spacing: 4, onColor: true)
                        .frame(width: 96, height: 92)
                        .padding(6)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if isCardio {
                    Image(systemName: day.cardioType.symbol)
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 96, height: 92)
                }
            }

            if !isCardio && !exercises.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(exercises.prefix(4)) { ex in
                        HStack {
                            Circle().fill(.white.opacity(0.7)).frame(width: 5, height: 5)
                            Text(ex.exerciseName)
                                .lineLimit(1)
                            Spacer()
                            Text("\(ex.targetSets) × \(ex.repRangeText)")
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    }
                    if exercises.count > 4 {
                        Text("+ \(exercises.count - 4) more")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.leading, 13)
                    }
                    if day.includesCardio {
                        Label("Finish with a \(Fmt.miles(day.cardioDistance)) mi \(day.cardioType.displayName.lowercased()) run", systemImage: "figure.run")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.top, 2)
                    }
                }
                .padding(12)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if !isCardio {
                Text("No exercises yet. Add some in the Plan tab, or start and add as you go.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }

            HStack(spacing: 10) {
                Button(action: onStart) {
                    Label(isCardio ? "Log Run" : "Start Workout", systemImage: isCardio ? "figure.run" : "play.fill")
                        .font(.headline)
                        .foregroundStyle(isCardio ? Theme.cardio : Theme.ember)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                Menu {
                    if !isWeekly {
                        Button("Skip to Next Day", systemImage: "forward.fill", action: onSkip)
                    }
                    Section(isWeekly ? "Do a different workout" : "Do a different day next") {
                        ForEach(split.orderedDays.filter { $0.id != day.id && $0.kind != .rest }) { other in
                            Button(other.displayName, systemImage: other.kind.symbol) { onPick(other) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(Theme.cardPadding)
        .background(isCardio ? Theme.cardioGradient : Theme.accentGradient,
                    in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: (isCardio ? Theme.cardio : Theme.ember).opacity(0.35), radius: 18, y: 10)
    }

    private var subtitle: String {
        if day.kind == .cardio {
            return "\(Fmt.miles(day.cardioDistance)) mi · \(day.cardioType.displayName) · \(split.name)"
        }
        let count = day.orderedExercises.count
        return "\(count) exercises · ~\(day.estimatedMinutes) min · \(split.name)"
    }
}

private struct RestDayCard: View {
    let split: WorkoutSplit
    let nextUp: SplitDay?
    let nextDate: Date?
    var onTrainAnyway: (SplitDay) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("REST DAY")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Recover & recharge")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Muscle is built between sessions. Sleep, eat, and come back stronger.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolEffect(.breathe)
            }
            if let nextUp {
                HStack {
                    Label {
                        Text("Next: **\(nextUp.displayName)**\(nextDate.map { " · \(Fmt.relativeDay($0) == "Today" ? "Today" : $0.formatted(.dateTime.weekday(.wide)))" } ?? "")")
                    } icon: {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    Spacer()
                    Button("Train Anyway") { onTrainAnyway(nextUp) }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.rest)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.white, in: Capsule())
                }
                .padding(12)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(Theme.cardPadding)
        .background(Theme.restGradient, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: Theme.rest.opacity(0.35), radius: 18, y: 10)
    }
}

private struct DoneTodayCard: View {
    let completed: [SplitDay]
    let nextUp: SplitDay?
    let nextDate: Date?
    let sessionsToday: [HistorySnapshot.SessionEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: completed.count)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DONE FOR TODAY")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(completed.map(\.displayName).joined(separator: " + "))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            if let session = sessionsToday.first {
                HStack(spacing: 18) {
                    stat(Fmt.duration(session.duration), "time")
                    stat(Fmt.volume(session.volume), "lb lifted")
                    stat("\(session.workingSets)", "sets")
                    if session.prCount > 0 { stat("\(session.prCount)", "PRs") }
                }
            }
            if let nextUp {
                Label("Next up: \(nextUp.displayName)\(nextDate.map { " · \($0.formatted(.dateTime.weekday(.wide)))" } ?? "")",
                      systemImage: "arrow.right.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(Theme.cardPadding)
        .background(
            LinearGradient(colors: [Color(red: 0.25, green: 0.85, blue: 0.55), Color(red: 0.10, green: 0.62, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        )
        .shadow(color: Theme.success.opacity(0.35), radius: 18, y: 10)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.8))
        }
    }
}

private struct NoSplitCard: View {
    var onTemplates: () -> Void
    var onBuild: () -> Void
    var onQuick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            IconBadge(systemName: "sparkles", size: 48)
            Text("Let's set up your training")
                .font(.title2.weight(.bold))
            Text("Pick a proven template or build your own split. You can always jump straight into a quick workout too.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Browse Templates", action: onTemplates)
                .buttonStyle(PrimaryButtonStyle())
            HStack(spacing: 10) {
                Button("Build My Own", action: onBuild)
                    .buttonStyle(SecondaryButtonStyle())
                Button("Quick Workout", action: onQuick)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .cardStyle()
    }
}

/// Template list used from Today when there's no split yet.
struct TemplateGallery: View {
    var onDone: () -> Void
    @State private var preview: SplitTemplate?

    var body: some View {
        List(SplitTemplate.all) { template in
            Button {
                preview = template
            } label: {
                HStack(spacing: 14) {
                    IconBadge(systemName: template.icon, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(template.name).font(.headline).foregroundStyle(.primary)
                        Text(template.daysPerWeek).font(.caption.weight(.semibold)).foregroundStyle(Theme.ember)
                        Text(template.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close", action: onDone) }
        }
        .sheet(item: $preview) { template in
            TemplatePreviewSheet(template: template) { _ in onDone() }
        }
    }
}

struct SessionSummaryRow: View {
    let session: HistorySnapshot.SessionEntry

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(session.start.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.ember)
                Text(session.start.formatted(.dateTime.day()))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .frame(width: 46, height: 50)
            .background(Theme.ember.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if session.prCount > 0 {
                        Label("\(session.prCount)", systemImage: "trophy.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.gold)
                    }
                }
                Text("\(Fmt.duration(session.duration)) · \(Fmt.volume(session.volume)) lb · \(session.workingSets) sets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.exercises.map(\.name).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .cardStyle(padding: 14)
    }
}
