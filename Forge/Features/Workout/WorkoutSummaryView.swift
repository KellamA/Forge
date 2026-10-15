import SwiftUI

/// Shown after finishing a workout.
struct WorkoutSummaryView: View {
    @Bindable var session: WorkoutSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var showConfetti = false

    private static let ratings = ["😮‍💨", "😕", "🙂", "💪", "🔥"]

    var body: some View {
        let prSets = session.orderedExercises.flatMap { ex in ex.completedSets.filter { $0.prKind != nil }.map { (ex, $0) } }
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header(prCount: prSets.count)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        StatTile(title: "Duration", value: Fmt.duration(session.duration), icon: "timer")
                        StatTile(title: "Volume", value: Fmt.volume(session.totalVolume), unit: "lb", icon: "scalemass.fill")
                        StatTile(title: "Working Sets", value: "\(session.workingSetCount)", icon: "square.stack.3d.up.fill")
                        StatTile(title: "PRs", value: "\(prSets.count)", icon: "trophy.fill", tint: Theme.gold)
                    }

                    if !prSets.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Personal Records", systemImage: "trophy.fill")
                                .font(.headline)
                                .foregroundStyle(Theme.gold)
                            ForEach(prSets, id: \.1.id) { ex, set in
                                HStack {
                                    Text(ex.exerciseName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(prText(ex, set))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .cardStyle()
                    }

                    if !muscleIntensities.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Muscles Worked")
                                .font(.headline)
                            BodyMapView(intensities: muscleIntensities, spacing: 30)
                                .frame(height: 220)
                                .frame(maxWidth: .infinity)
                        }
                        .cardStyle()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Exercises")
                            .font(.headline)
                        ForEach(session.orderedExercises) { ex in
                            HStack(alignment: .firstTextBaseline) {
                                Text(ex.exerciseName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(ex.completedSets.filter { !$0.isWarmup }.map { ExerciseStats.setText(
                                    SetSnapshot(weight: $0.weight, reps: $0.reps, seconds: $0.seconds, isWarmup: false), tracking: ex.tracking) }
                                    .joined(separator: ", "))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        ForEach(session.cardio ?? []) { log in
                            HStack {
                                Label("\(log.type.displayName) Run", systemImage: log.type.symbol)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(Fmt.miles(log.distance)) mi")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("How did it feel?")
                            .font(.headline)
                        HStack {
                            ForEach(1...5, id: \.self) { value in
                                Button {
                                    withAnimation(.snappy) { session.rating = value }
                                } label: {
                                    Text(Self.ratings[value - 1])
                                        .font(.system(size: 30))
                                        .frame(maxWidth: .infinity, minHeight: 52)
                                        .background(session.rating == value ? Theme.ember.opacity(0.2) : Color.subtleFill,
                                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(session.rating == value ? Theme.ember : .clear, lineWidth: 2))
                                        .scaleEffect(session.rating == value ? 1.05 : 1)
                                }
                                .buttonStyle(.plain)
                                .sensoryFeedback(.selection, trigger: session.rating)
                            }
                        }
                        TextField("Notes (optional)", text: $session.notes, axis: .vertical)
                            .lineLimit(2...5)
                            .padding(12)
                            .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .cardStyle()
                }
                .padding(16)
            }
            .screenBackground()
            .safeAreaInset(edge: .bottom) {
                Button("Done") {
                    try? context.save()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .overlay {
                if showConfetti {
                    ConfettiView()
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
            }
            .onAppear {
                if !prSets.isEmpty { showConfetti = true }
            }
            .onDisappear { try? context.save() }
        }
        .sensoryFeedback(.success, trigger: showConfetti)
    }

    private func header(prCount: Int) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 92, height: 92)
                    .shadow(color: Theme.ember.opacity(0.45), radius: 20, y: 8)
                Image(systemName: prCount > 0 ? "trophy.fill" : "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: showConfetti)
            }
            Text(prCount > 0 ? "New Personal Best!" : "Workout Complete")
                .font(.title.weight(.bold))
            Text("\(session.name) · \(session.startedAt.formatted(.dateTime.weekday(.wide).month().day()))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    private var muscleIntensities: [Muscle: Double] {
        var sets: [Muscle: Double] = [:]
        for ex in session.orderedExercises {
            let count = Double(ex.completedSets.filter { !$0.isWarmup }.count)
            for m in ex.primaryMuscles { sets[m, default: 0] += count }
            for m in ex.secondaryMuscles { sets[m, default: 0] += count * 0.5 }
        }
        let top = sets.values.max() ?? 1
        return sets.filter { $0.value > 0 }.mapValues { 0.3 + 0.7 * $0 / top }
    }

    private func prText(_ ex: SessionExercise, _ set: SetLog) -> String {
        switch ex.tracking {
        case .weightReps:
            let e1rm = OneRepMax.estimate(weight: set.weight, reps: set.reps, formula: .current) ?? set.weight
            return "\(Fmt.weight(set.weight)) × \(set.reps) · e1RM \(Fmt.weight(e1rm.rounded()))"
        case .bodyweight:
            return "\(set.reps) reps"
        case .duration:
            return "\(set.seconds)s hold"
        }
    }
}

/// Lightweight falling-confetti celebration.
struct ConfettiView: View {
    private struct Piece {
        let x: Double
        let delay: Double
        let speed: Double
        let spin: Double
        let size: Double
        let color: Color
        let drift: Double
    }

    @State private var start = Date()
    private let pieces: [Piece] = (0..<90).map { _ in
        Piece(x: .random(in: 0...1), delay: .random(in: 0...0.8), speed: .random(in: 0.35...0.7),
              spin: .random(in: 2...8), size: .random(in: 6...11),
              color: [Theme.gold, Theme.ember, Theme.flame, Theme.cardio, Theme.success, Theme.body].randomElement()!,
              drift: .random(in: -40...40))
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for piece in pieces {
                    let local = t - piece.delay
                    guard local > 0, local < 4 else { continue }
                    let y = -20 + local * piece.speed * size.height
                    let x = piece.x * size.width + sin(local * 2 + piece.spin) * piece.drift
                    let opacity = max(0, 1 - max(0, local - 2.8))
                    var ctx = context
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .radians(local * piece.spin))
                    ctx.opacity = opacity
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(piece.color))
                }
            }
        }
    }
}
