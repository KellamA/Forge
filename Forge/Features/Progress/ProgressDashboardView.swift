import Charts
import SwiftData
import SwiftUI

struct ProgressDashboardView: View {
    @Environment(HistoryStore.self) private var history
    @AppStorage(SettingsKey.weeklyGoal) private var weeklyGoal = SettingsDefaults.weeklyGoal
    @AppStorage("progressExerciseID") private var selectedExerciseID = ""
    @State private var strengthRange: ChartRange = .quarter
    @State private var muscleWindow: MuscleWindow = .week

    enum MuscleWindow: String, CaseIterable, Identifiable {
        case week = "7 Days", month = "30 Days", quarter = "90 Days"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : (self == .month ? 30 : 90) }
    }

    private var snapshot: HistorySnapshot { history.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if snapshot.isEmpty && history.hasLoaded {
                        EmptyStateCard(icon: "chart.line.uptrend.xyaxis", title: "Your progress lives here",
                                       message: "Finish a workout and you'll see strength trends, weekly volume, muscle balance and personal records.")
                    } else {
                        summaryGrid
                        strengthCard
                        weeklyCard
                        muscleCard
                        consistencyCard
                        cardioCard
                        linksCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .navigationTitle("Progress")
            .navigationDestination(for: SessionLink.self) { SessionDetailView(sessionID: $0.id) }
            .navigationDestination(for: HistoryLink.self) { _ in HistoryView() }
            .navigationDestination(for: RecordsLink.self) { _ in RecordsView() }
            .navigationDestination(for: ExerciseLink.self) { ExerciseDetailView(exerciseID: $0.id) }
        }
    }

    // MARK: - Summary

    private var summaryGrid: some View {
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        let recent = snapshot.sessions(since: monthAgo)
        let miles = snapshot.cardio.filter { $0.date >= monthAgo }.reduce(0) { $0 + $1.distance }
        let minutes = recent.reduce(0) { $0 + $1.duration } / 60
        let prs = recent.reduce(0) { $0 + $1.prCount }
        let sets = recent.reduce(0) { $0 + $1.workingSets }
        let prExercises = Set(recent.flatMap { s in s.exercises.filter { ex in ex.sets.contains(where: \.isPR) }.map(\.exerciseID) }).count
        let runs = snapshot.cardio.filter { $0.date >= monthAgo }.count
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Last 30 Days")
            // Every tile has a footnote so all four are the same height.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                StatTile(title: "Workouts", value: "\(recent.count)", icon: "dumbbell.fill",
                         footnote: "\(Fmt.duration(minutes * 60)) training")
                StatTile(title: "Volume", value: Fmt.volume(recent.reduce(0) { $0 + $1.volume }), unit: "lb", icon: "scalemass.fill",
                         footnote: "\(sets) working sets")
                StatTile(title: "PRs", value: "\(prs)", icon: "trophy.fill", tint: Theme.gold,
                         footnote: prExercises == 1 ? "1 exercise" : "\(prExercises) exercises")
                StatTile(title: "Distance Run", value: Fmt.miles(miles), unit: "mi", icon: "figure.run", tint: Theme.cardio,
                         footnote: runs == 1 ? "1 run" : "\(runs) runs")
            }
        }
    }

    // MARK: - Strength

    private var strengthCard: some View {
        let exercises = snapshot.loggedExercises()
        let current = exercises.first { $0.id == selectedExerciseID } ?? exercises.first { $0.tracking == .weightReps } ?? exercises.first
        let start = strengthRange.startDate
        let points = current.map { snapshot.trend(for: $0.id) }?.filter { start == nil || $0.date >= start! } ?? []
        let unit = current.map { HistorySnapshot.unit(for: $0.tracking) } ?? "lb"
        let change = (points.last?.value ?? 0) - (points.first?.value ?? 0)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Strength")
                    .font(.headline)
                Spacer()
                if !exercises.isEmpty {
                    Menu {
                        ForEach(exercises, id: \.id) { ex in
                            Button {
                                selectedExerciseID = ex.id
                            } label: {
                                if ex.id == current?.id {
                                    Label(ex.name, systemImage: "checkmark")
                                } else {
                                    Text("\(ex.name) (\(ex.count))")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(current?.name ?? "Choose")
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ember)
                    }
                }
            }
            if let current {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.tracking == .weightReps ? "ESTIMATED 1RM" : (current.tracking == .bodyweight ? "BEST REPS" : "LONGEST HOLD"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(points.last.map { Fmt.weight($0.value.rounded()) } ?? "–")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text(unit)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if points.count >= 2 {
                        Label("\(Fmt.signed(change.rounded(), digits: 0)) \(unit)", systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(change >= 0 ? Theme.success : .red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((change >= 0 ? Theme.success : .red).opacity(0.12), in: Capsule())
                    }
                }
                if points.count >= 2 {
                    TrendChart(points: points, tint: Theme.ember, unit: unit, height: 200)
                } else {
                    Text("Not enough sessions in this range yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                RangePicker(range: $strengthRange)
                NavigationLink(value: ExerciseLink(id: current.id)) {
                    HStack {
                        Text("Rep maxes, history & details")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ember)
                }
                if current.tracking == .weightReps {
                    Text("Estimated 1RM uses the \(OneRepMaxFormula.current.displayName.components(separatedBy: " ").first ?? "") formula on your best set each session. Change it in Settings.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Weekly

    private var weeklyCard: some View {
        let weeks = snapshot.weeks(12)
        let avg = weeks.isEmpty ? 0 : Double(weeks.reduce(0) { $0 + $1.workouts }) / Double(weeks.count)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Training Frequency")
                        .font(.headline)
                    Text("Avg \(avg.formatted(.number.precision(.fractionLength(1)))) sessions / week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Chart {
                ForEach(weeks) { week in
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Workouts", week.workouts))
                        .foregroundStyle(week.workouts >= weeklyGoal ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.ember.opacity(0.35)))
                        .cornerRadius(6)
                }
                RuleMark(y: .value("Goal", weeklyGoal))
                    .foregroundStyle(Theme.success)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal \(weeklyGoal)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.success)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 150)

            Divider()

            Text("Weekly Volume")
                .font(.subheadline.weight(.semibold))
            Chart(weeks) { week in
                AreaMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Volume", week.volume))
                    .foregroundStyle(LinearGradient(colors: [Theme.ember.opacity(0.35), Theme.ember.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Volume", week.volume))
                    .foregroundStyle(Theme.ember)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Volume", week.volume))
                    .foregroundStyle(Theme.ember)
                    .symbolSize(20)
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    AxisValueLabel { if let v = value.as(Double.self) { Text(Fmt.volume(v)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 140)
        }
        .cardStyle()
    }

    // MARK: - Muscles

    private var muscleCard: some View {
        let since = Calendar.current.date(byAdding: .day, value: -muscleWindow.days, to: .now)!
        let raw = snapshot.muscleSets(since: since)
        let weeksInWindow = Double(muscleWindow.days) / 7
        let perWeek = raw.mapValues { $0 / weeksInWindow }
        let intensities = perWeek.mapValues { min(1, $0 / 20) }
        let rows = Muscle.displayOrder.filter { $0 != .neck && $0 != .abductors || (perWeek[$0] ?? 0) > 0 }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Muscle Balance")
                        .font(.headline)
                    Text("Working sets per week (secondary muscles count half)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Picker("Window", selection: $muscleWindow) {
                ForEach(MuscleWindow.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            BodyMapView(intensities: intensities, spacing: 30, showsLabels: true)
                .frame(height: 230)
                .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                Text("0")
                LinearGradient(colors: [Theme.ember.opacity(0.25), Theme.ember], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 6)
                    .clipShape(Capsule())
                Text("20+ sets/wk")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            VStack(spacing: 9) {
                ForEach(rows) { muscle in
                    MuscleVolumeRow(muscle: muscle, setsPerWeek: perWeek[muscle] ?? 0)
                }
            }
            Text("10–20 hard sets per muscle per week is a common target for growth.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    // MARK: - Consistency

    private var consistencyCard: some View {
        let calendar = Calendar.current
        let weeksShown = 20
        let thisWeek = calendar.startOfWeek(for: .now)
        let firstWeek = calendar.date(byAdding: .weekOfYear, value: -(weeksShown - 1), to: thisWeek)!
        let liftDays = Set(snapshot.sessions.map { calendar.startOfDay(for: $0.start) })
        let cardioDays = Set(snapshot.cardio.map { calendar.startOfDay(for: $0.date) })
        let total = liftDays.union(cardioDays).filter { $0 >= firstWeek }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Consistency")
                        .font(.headline)
                    Text("\(total) active days in the last \(weeksShown) weeks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("\(snapshot.weeklyStreak(goal: weeklyGoal)) wk streak", systemImage: "flame.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.ember)
            }
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeksShown, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = calendar.date(byAdding: .day, value: w * 7 + d, to: firstWeek)!
                            let lifted = liftDays.contains(day)
                            let ran = cardioDays.contains(day)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(lifted ? Theme.ember : (ran ? Theme.cardio : Color.subtleFill.opacity(day > .now ? 0.3 : 1)))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                legend(Theme.ember, "Lifting")
                legend(Theme.cardio, "Cardio")
                legend(Color.subtleFill, "Rest")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
        }
    }

    // MARK: - Cardio

    @ViewBuilder
    private var cardioCard: some View {
        if !snapshot.cardio.isEmpty {
            let weeks = snapshot.weeks(12)
            let totalMiles = snapshot.cardio.reduce(0) { $0 + $1.distance }
            let bestPace = snapshot.cardio.compactMap(\.pace).min()
            let longest = snapshot.cardio.map(\.distance).max() ?? 0
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Running", systemImage: "figure.run")
                        .font(.headline)
                        .foregroundStyle(Theme.cardio)
                    Spacer()
                }
                HStack(spacing: 10) {
                    cardioStat(Fmt.miles(totalMiles), "total mi")
                    cardioStat(bestPace.map { Fmt.pace($0).replacingOccurrences(of: " /mi", with: "") } ?? "–", "best pace")
                    cardioStat(Fmt.miles(longest), "longest mi")
                }
                Chart(weeks) { week in
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Miles", week.miles))
                        .foregroundStyle(Theme.cardioGradient)
                        .cornerRadius(5)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 120)
                Text("Miles per week")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .cardStyle()
        }
    }

    private func cardioStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.cardio.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Links

    private var linksCard: some View {
        VStack(spacing: 0) {
            NavigationLink(value: RecordsLink()) {
                linkRow(icon: "trophy.fill", tint: Theme.gold, title: "Personal Records", subtitle: "\(snapshot.records().count) exercises")
            }
            Divider().padding(.leading, 56)
            NavigationLink(value: HistoryLink()) {
                linkRow(icon: "calendar", tint: Theme.ember, title: "Workout History", subtitle: "\(snapshot.sessions.count) workouts logged")
            }
        }
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func linkRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .contentShape(Rectangle())
    }
}

struct RecordsLink: Hashable {}
struct ExerciseLink: Hashable { let id: String }

private struct MuscleVolumeRow: View {
    let muscle: Muscle
    let setsPerWeek: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(muscle.displayName)
                .font(.caption.weight(.semibold))
                .frame(width: 82, alignment: .leading)
            GeometryReader { geo in
                let maxSets = 25.0
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.subtleFill)
                    // Target zone 10–20 sets.
                    Rectangle()
                        .fill(Theme.success.opacity(0.18))
                        .frame(width: w * 10 / maxSets)
                        .offset(x: w * 10 / maxSets)
                    if setsPerWeek > 0 {
                        Capsule()
                            .fill(muscle.group.color.gradient)
                            .frame(width: max(6, w * min(1, setsPerWeek / maxSets)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            Text(setsPerWeek.formatted(.number.precision(.fractionLength(0...1))))
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(width: 30, alignment: .trailing)
                .foregroundStyle(setsPerWeek >= 10 ? .primary : .secondary)
        }
    }
}
