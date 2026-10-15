import SwiftData
import SwiftUI

struct ExerciseDetailView: View {
    let exerciseID: String

    @Environment(ExerciseLibrary.self) private var library
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [SessionExercise]
    @Query private var favoriteRecords: [FavoriteExercise]
    @Query private var customExercises: [CustomExercise]
    @AppStorage(SettingsKey.oneRepMaxFormula) private var formulaRaw = OneRepMaxFormula.brzycki.rawValue
    @State private var range: ChartRange = .all
    @State private var editingCustom: CustomExercise?
    @State private var confirmDelete = false
    @State private var showAllHistory = false

    init(exerciseID: String) {
        self.exerciseID = exerciseID
        _entries = Query(filter: #Predicate<SessionExercise> { $0.exerciseID == exerciseID })
        _favoriteRecords = Query(filter: #Predicate<FavoriteExercise> { $0.exerciseID == exerciseID })
    }

    private var info: ExerciseInfo {
        library.exercise(id: exerciseID) ?? .placeholder(id: exerciseID, name: entries.first?.exerciseName ?? "Exercise")
    }

    private var formula: OneRepMaxFormula { OneRepMaxFormula(rawValue: formulaRaw) ?? .brzycki }
    private var isFavorite: Bool { !favoriteRecords.isEmpty }

    var body: some View {
        let stats = ExerciseStats(entries: entries, tracking: info.tracking, formula: formula)
        ScrollView {
            VStack(spacing: 16) {
                hero
                if !stats.points.isEmpty {
                    statsCard(stats)
                    if info.tracking == .weightReps, let best = stats.best {
                        repMaxCard(oneRM: best.value)
                    }
                    historyCard(stats)
                }
                if !info.instructions.isEmpty {
                    instructionsCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(info.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? Theme.gold : .primary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .sensoryFeedback(.impact(weight: .light), trigger: isFavorite)
                .accessibilityLabel(isFavorite ? "Remove Favorite" : "Add Favorite")
            }
            if info.isCustom, let custom = customExercises.first(where: { $0.exerciseID == exerciseID }) {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Edit", systemImage: "pencil") { editingCustom = custom }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .sheet(item: $editingCustom) { custom in
            CustomExerciseEditor(existing: custom)
        }
        .confirmationDialog("Delete this exercise?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Exercise", role: .destructive) {
                if let custom = customExercises.first(where: { $0.exerciseID == exerciseID }) {
                    context.delete(custom)
                    try? context.save()
                    dismiss()
                }
            }
        } message: {
            Text("Your logged history for it stays in your workouts.")
        }
    }

    // MARK: Sections

    private var hero: some View {
        VStack(spacing: 14) {
            BodyMapView(intensities: info.muscleIntensities, spacing: 24, showsLabels: true)
                .frame(height: 280)
                .padding(.top, 8)
            BodyMapLegend()
            VStack(alignment: .leading, spacing: 8) {
                if !info.primary.isEmpty {
                    muscleRow(title: "Primary", muscles: info.primary, filled: true)
                }
                if !info.secondary.isEmpty {
                    muscleRow(title: "Secondary", muscles: info.secondary, filled: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(text: info.equipment.displayName, icon: info.equipment.symbol, tint: .primary)
                    Chip(text: info.category.displayName, icon: "tag.fill", tint: .primary)
                    Chip(text: info.tracking.displayName, icon: "ruler.fill", tint: .primary)
                    if let level = info.level {
                        Chip(text: level.capitalized, icon: "chart.bar.fill", tint: .primary)
                    }
                    if let mechanic = info.mechanic {
                        Chip(text: mechanic.capitalized, icon: "link", tint: .primary)
                    }
                    if info.isCustom {
                        Chip(text: "Custom", icon: "person.fill", tint: Theme.ember)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func muscleRow(title: String, muscles: [Muscle], filled: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            FlowLayout(spacing: 6) {
                ForEach(muscles) { m in
                    Chip(text: m.displayName, tint: Theme.ember, filled: filled)
                }
            }
        }
    }

    private func statsCard(_ stats: ExerciseStats) -> some View {
        let start = range.startDate
        let points = stats.points
            .filter { start == nil || $0.date >= start! }
            .map { TrendPoint(id: $0.id, date: $0.date, value: $0.value,
                              label: "\(Fmt.weight($0.topWeight)) × \($0.topReps) · \($0.date.formatted(.dateTime.month(.abbreviated).day()))") }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.valueTitle.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(stats.latest.map { Fmt.weight($0.value.rounded()) } ?? "–")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(stats.valueUnit)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    if let change = stats.recentChange {
                        Label("\(Fmt.signed(change.rounded(), digits: 0)) \(stats.valueUnit) in 30 days", systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(change >= 0 ? Theme.success : .red)
                    }
                }
                Spacer()
                if let best = stats.best {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("ALL-TIME BEST")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("\(Fmt.weight(best.value.rounded())) \(stats.valueUnit)")
                            .font(.headline)
                            .foregroundStyle(Theme.accentGradient)
                        Text(best.date.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if points.count >= 2 {
                TrendChart(points: points, tint: Theme.ember, unit: stats.valueUnit, height: 190)
                RangePicker(range: $range)
            } else {
                Text("Log this exercise a few more times to see your trend.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                miniStat("Sessions", "\(stats.points.count)")
                miniStat("Sets", "\(stats.totalSets)")
                if info.tracking == .weightReps {
                    miniStat("Heaviest", "\(Fmt.weight(stats.heaviest)) lb")
                    miniStat("Volume", Fmt.volume(stats.totalVolume))
                } else {
                    miniStat("Total Reps", "\(stats.totalReps)")
                }
            }
        }
        .cardStyle()
    }

    private func miniStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.subtleFill.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func repMaxCard(oneRM: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rep Max Estimates")
                    .font(.headline)
                Spacer()
                Text(formula.displayName.components(separatedBy: " ").first ?? "")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("What your best set suggests you can lift for each rep count.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(OneRepMax.tableReps, id: \.self) { reps in
                    let w = OneRepMax.weight(forReps: reps, oneRepMax: oneRM, formula: formula)
                    VStack(spacing: 2) {
                        Text("\(reps)RM")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(reps == 1 ? Theme.ember : .secondary)
                        Text(Fmt.weight((w / 2.5).rounded() * 2.5))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(reps == 1 ? Theme.ember.opacity(0.12) : Color.subtleFill.opacity(0.7),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .cardStyle()
    }

    private func historyCard(_ stats: ExerciseStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.headline)
            let sessions = showAllHistory ? stats.sessions : Array(stats.sessions.prefix(5))
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(session.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.subheadline.weight(.semibold))
                        Text(session.sessionName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    FlowLayout(spacing: 6) {
                        ForEach(Array(session.sets.enumerated()), id: \.offset) { index, set in
                            HStack(spacing: 3) {
                                if index == session.prSetIndex {
                                    Image(systemName: "trophy.fill").foregroundStyle(Theme.gold)
                                }
                                Text(ExerciseStats.setText(set, tracking: info.tracking))
                            }
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundStyle(set.isWarmup ? .secondary : .primary)
                            .background(Color.subtleFill.opacity(set.isWarmup ? 0.4 : 0.8), in: Capsule())
                        }
                    }
                }
                if session.id != sessions.last?.id { Divider() }
            }
            if stats.sessions.count > 5 {
                Button(showAllHistory ? "Show Less" : "Show All \(stats.sessions.count) Sessions") {
                    withAnimation(.snappy) { showAllHistory.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .cardStyle()
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How To")
                .font(.headline)
            ForEach(Array(info.instructions.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Theme.accentGradient, in: Circle())
                    Text(step)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .cardStyle()
    }

    private func toggleFavorite() {
        if favoriteRecords.isEmpty {
            context.insert(FavoriteExercise(exerciseID: exerciseID))
        } else {
            favoriteRecords.forEach { context.delete($0) }
        }
        try? context.save()
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
