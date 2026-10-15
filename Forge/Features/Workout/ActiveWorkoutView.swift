import SwiftData
import SwiftUI

enum SetField: Hashable {
    case weight(UUID)
    case reps(UUID)
    case seconds(UUID)

    var setID: UUID {
        switch self {
        case .weight(let id), .reps(let id), .seconds(let id): id
        }
    }
}

struct PlateTarget: Identifiable {
    let id = UUID()
    let weight: Double
}

struct ActiveWorkoutView: View {
    @Environment(WorkoutManager.self) private var manager
    @Environment(ExerciseLibrary.self) private var library
    @Environment(\.modelContext) private var context

    @FocusState private var focus: SetField?
    @State private var showingPicker = false
    @State private var replacing: SessionExercise?
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var showingReorder = false
    @State private var plateTarget: PlateTarget?
    @State private var infoExerciseID: String?
    @State private var cardioPrefill: CardioPrefill?
    @State private var prBanner: String?
    /// Bumped when the keyboard +/- buttons change a focused field, so it re-reads its value.
    @State private var adjustTick = 0
    @AppStorage(SettingsKey.weightIncrement) private var increment = SettingsDefaults.weightIncrement

    var body: some View {
        NavigationStack {
            Group {
                if let session = manager.activeSession {
                    content(session)
                } else {
                    ContentUnavailableView("No Workout in Progress", systemImage: "dumbbell",
                                           description: Text("Start one from the Today tab."))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { manager.addExercises($0) }
        }
        .sheet(item: $replacing) { ex in
            ExercisePickerView(title: "Replace Exercise", allowsMultiple: false) { picked in
                if let info = picked.first { manager.replace(ex, with: info) }
            }
        }
        .sheet(isPresented: $showingReorder) {
            if let session = manager.activeSession {
                ReorderExercisesSheet(exercises: session.orderedExercises) { manager.move($0) }
            }
        }
        .sheet(item: $plateTarget) { target in
            PlateCalculatorView(initialWeight: target.weight)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: Binding(get: { infoExerciseID.map { IdentifiedString(value: $0) } },
                             set: { infoExerciseID = $0?.value })) { item in
            NavigationStack {
                ExerciseDetailView(exerciseID: item.value)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { infoExerciseID = nil }
                        }
                    }
            }
        }
        .sheet(item: $cardioPrefill) { prefill in
            CardioLogView(prefill: prefill)
        }
        .confirmationDialog("Finish workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish Workout") { finish() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("\(unfinishedCount) unfinished \(unfinishedCount == 1 ? "set" : "sets") won't be saved.")
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Workout", role: .destructive) { manager.discard() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Nothing from this session will be saved.")
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: manager.restFinishedTick)
        .sensoryFeedback(.success, trigger: manager.prTick)
        .onChange(of: focus) { _, _ in
            manager.refreshLiveActivity()
        }
        .onChange(of: manager.prTick) {
            guard let message = manager.latestPRMessage else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { prBanner = message }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                withAnimation(.easeOut) { if prBanner == message { prBanner = nil } }
            }
        }
    }

    // MARK: - Content

    private func content(_ session: WorkoutSession) -> some View {
        List {
            Section {
                WorkoutHeaderView(session: session)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            ForEach(session.orderedExercises) { exercise in
                Section {
                    ExerciseHeaderRow(
                        exercise: exercise,
                        info: library.exercise(id: exercise.exerciseID),
                        hint: manager.hint(for: exercise),
                        onInfo: { infoExerciseID = exercise.exerciseID },
                        onReplace: { replacing = exercise },
                        onRemove: { withAnimation { manager.remove(exercise) } },
                        onReorder: { showingReorder = true },
                        onPlates: {
                            let w = exercise.orderedSets.first(where: { !$0.isCompleted })?.weight ?? exercise.orderedSets.last?.weight ?? 135
                            plateTarget = PlateTarget(weight: w)
                        }
                    )
                    SetColumnsHeader(tracking: exercise.tracking)
                    let previous = manager.previous(for: exercise).filter { !$0.isWarmup }
                    ForEach(Array(exercise.orderedSets.enumerated()), id: \.element.id) { index, set in
                        let workingIndex = exercise.orderedSets.prefix(index).filter { !$0.isWarmup }.count
                        SetRowView(
                            set: set,
                            number: workingIndex + 1,
                            tracking: exercise.tracking,
                            previous: set.isWarmup ? nil : (workingIndex < previous.count ? previous[workingIndex] : nil),
                            focus: $focus,
                            adjustTick: adjustTick,
                            onToggle: {
                                withAnimation(.snappy) { manager.toggleComplete(set) }
                            },
                            onWarmup: { manager.toggleWarmup(set) },
                            onDelete: { withAnimation { manager.delete(set) } },
                            onPlates: { plateTarget = PlateTarget(weight: set.weight) }
                        )
                        .listRowBackground(set.isCompleted ? Theme.success.opacity(0.13) : Color.cardBackground)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation { manager.delete(set) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    Button {
                        withAnimation(.snappy) { manager.addSet(to: exercise) }
                    } label: {
                        Label("Add Set", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                    .tint(Theme.ember)
                }
            }

            cardioSection(session)

            Section {
                Button {
                    showingPicker = true
                } label: {
                    Label("Add Exercises", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(Theme.ember)
                Button {
                    cardioPrefill = CardioPrefill(linkToActiveSession: true)
                } label: {
                    Label("Add Cardio", systemImage: "figure.run")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(Theme.cardio)
            }

            Section {
                Button("Finish Workout") { attemptFinish() }
                    .buttonStyle(PrimaryButtonStyle())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                Button("Discard Workout", role: .destructive) { confirmDiscard = true }
                    .frame(maxWidth: .infinity)
                    .font(.subheadline.weight(.semibold))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if manager.restEndsAt != nil {
                    RestTimerBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let focus {
                    EntryBar(stepLabel: stepLabel(for: focus),
                             onMinus: { adjustFocused(by: -1) },
                             onPlus: { adjustFocused(by: 1) },
                             onNext: { moveFocusForward() },
                             onDone: { self.focus = nil })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: focus == nil)
        }
        .overlay(alignment: .top) {
            if let prBanner {
                PRBanner(text: prBanner)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.restEndsAt != nil)
    }

    @ViewBuilder
    private func cardioSection(_ session: WorkoutSession) -> some View {
        let logs = session.cardio ?? []
        let day = plannedDay(for: session)
        if !logs.isEmpty || day?.includesCardio == true {
            Section {
                HStack(spacing: 12) {
                    IconBadge(systemName: (day?.cardioType ?? .outdoor).symbol, gradient: Theme.cardioGradient, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cardio Finisher")
                            .font(.headline)
                        if let day, day.includesCardio {
                            Text("\(Fmt.miles(day.cardioDistance)) mi · \(day.cardioType.displayName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if logs.isEmpty {
                        Button("Log Run") {
                            cardioPrefill = CardioPrefill(type: day?.cardioType ?? .outdoor,
                                                          distance: day?.cardioDistance ?? 2,
                                                          linkToActiveSession: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.cardio)
                    }
                }
                ForEach(logs) { log in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                        Text("\(Fmt.miles(log.distance)) mi \(log.type.displayName)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let pace = log.pace {
                            Text(Fmt.pace(pace))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            context.delete(log)
                            try? context.save()
                        }
                    }
                }
            }
        }
    }

    private func plannedDay(for session: WorkoutSession) -> SplitDay? {
        guard let dayID = session.splitDayID else { return nil }
        let descriptor = FetchDescriptor<SplitDay>(predicate: #Predicate { $0.id == dayID })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                focus = nil
                manager.isPresented = false
            } label: {
                Image(systemName: "chevron.down")
            }
            .accessibilityLabel("Minimize Workout")
        }
        ToolbarItem(placement: .principal) {
            if let session = manager.activeSession {
                VStack(spacing: 0) {
                    Text(session.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(session.startedAt, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Finish") { attemptFinish() }
                .buttonStyle(.glassProminent)
                .tint(Theme.ember)
                .disabled(manager.activeSession == nil)
        }
    }

    // MARK: - Actions

    private var unfinishedCount: Int {
        manager.activeSession?.orderedExercises.flatMap(\.orderedSets).filter { !$0.isCompleted }.count ?? 0
    }

    private func attemptFinish() {
        focus = nil
        guard let session = manager.activeSession else { return }
        let completed = session.orderedExercises.flatMap(\.orderedSets).filter(\.isCompleted).count
        if completed == 0 && (session.cardio ?? []).isEmpty {
            confirmDiscard = true
        } else if unfinishedCount > 0 {
            confirmFinish = true
        } else {
            finish()
        }
    }

    private func finish() {
        manager.finish()
    }

    private var fieldOrder: [SetField] {
        guard let session = manager.activeSession else { return [] }
        var fields: [SetField] = []
        for ex in session.orderedExercises {
            for set in ex.orderedSets where !set.isCompleted {
                switch ex.tracking {
                case .weightReps, .bodyweight:
                    fields.append(.weight(set.id))
                    fields.append(.reps(set.id))
                case .duration:
                    fields.append(.seconds(set.id))
                }
            }
        }
        return fields
    }

    private func moveFocusForward() {
        guard let focus else { return }
        let order = fieldOrder
        if let i = order.firstIndex(of: focus), i + 1 < order.count {
            self.focus = order[i + 1]
        } else {
            self.focus = nil
        }
    }

    private func stepLabel(for field: SetField) -> String {
        switch field {
        case .weight: "\(Fmt.weight(increment)) lb"
        case .reps: "1 rep"
        case .seconds: "5 sec"
        }
    }

    private func adjustFocused(by direction: Double) {
        guard let focus, let session = manager.activeSession else { return }
        guard let set = session.orderedExercises.flatMap(\.orderedSets).first(where: { $0.id == focus.setID }) else { return }
        switch focus {
        case .weight: set.weight = max(0, set.weight + direction * increment)
        case .reps: set.reps = max(0, set.reps + Int(direction))
        case .seconds: set.seconds = max(0, set.seconds + Int(direction) * 5)
        }
        adjustTick += 1
    }
}

struct IdentifiedString: Identifiable {
    let value: String
    var id: String { value }
}

// MARK: - Header

private struct WorkoutHeaderView: View {
    @Bindable var session: WorkoutSession

    var body: some View {
        let sets = session.orderedExercises.flatMap(\.orderedSets)
        let done = sets.filter(\.isCompleted).count
        VStack(alignment: .leading, spacing: 12) {
            TextField("Workout name", text: $session.name)
                .font(.title2.weight(.bold))
            HStack(spacing: 18) {
                headerStat(icon: "timer", value: Text(session.startedAt, style: .timer))
                headerStat(icon: "square.stack.3d.up.fill", value: Text("\(done)/\(sets.count) sets"))
                headerStat(icon: "scalemass.fill", value: Text("\(Fmt.volume(session.totalVolume)) lb"))
            }
            ProgressView(value: Double(done), total: Double(max(1, sets.count)))
                .tint(Theme.ember)
                .animation(.snappy, value: done)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func headerStat(icon: String, value: Text) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(Theme.ember)
            value
                .monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
    }
}

private struct ExerciseHeaderRow: View {
    let exercise: SessionExercise
    let info: ExerciseInfo?
    let hint: String?
    var onInfo: () -> Void
    var onReplace: () -> Void
    var onRemove: () -> Void
    var onReorder: () -> Void
    var onPlates: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                MuscleThumbnail(primary: exercise.primaryMuscles, secondary: exercise.secondaryMuscles, size: 46)
                    .onTapGesture(perform: onInfo)
                VStack(alignment: .leading, spacing: 3) {
                    Button(action: onInfo) {
                        Text(exercise.exerciseName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 8) {
                        Text(exercise.targetText)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.ember)
                        if exercise.restSeconds > 0 {
                            Label(Fmt.restLabel(exercise.restSeconds), systemImage: "timer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Exercise Info", systemImage: "info.circle", action: onInfo)
                    if exercise.tracking == .weightReps {
                        Button("Plate Calculator", systemImage: "circle.grid.2x1", action: onPlates)
                    }
                    Menu("Rest Timer", systemImage: "timer") {
                        ForEach([0, 30, 60, 90, 120, 150, 180, 240, 300], id: \.self) { s in
                            Button {
                                exercise.restSeconds = s
                            } label: {
                                if exercise.restSeconds == s {
                                    Label(s == 0 ? "Off" : Fmt.restLabel(s), systemImage: "checkmark")
                                } else {
                                    Text(s == 0 ? "Off" : Fmt.restLabel(s))
                                }
                            }
                        }
                    }
                    Button("Reorder Exercises", systemImage: "arrow.up.arrow.down", action: onReorder)
                    Button("Replace Exercise", systemImage: "arrow.triangle.2.circlepath", action: onReplace)
                    Divider()
                    Button("Remove Exercise", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Color.subtleFill, in: Circle())
                        .foregroundStyle(.primary)
                }
            }
            if !exercise.notes.isEmpty {
                Label(exercise.notes, systemImage: "note.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let hint {
                Label(hint, systemImage: "arrow.up.forward.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.success)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SetColumnsHeader: View {
    let tracking: TrackingType

    var body: some View {
        HStack(spacing: 8) {
            Text("SET").frame(width: 30)
            Text("PREVIOUS").frame(width: 76)
            switch tracking {
            case .weightReps:
                Text("LB").frame(maxWidth: .infinity)
                Text("REPS").frame(width: 56)
            case .bodyweight:
                Text("+LB").frame(maxWidth: .infinity)
                Text("REPS").frame(width: 56)
            case .duration:
                Text("SECONDS").frame(maxWidth: .infinity)
            }
            Image(systemName: "checkmark").frame(width: 38)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden)
    }
}

// MARK: - Set row

struct SetRowView: View {
    @Bindable var set: SetLog
    let number: Int
    let tracking: TrackingType
    let previous: SetSnapshot?
    var focus: FocusState<SetField?>.Binding
    var adjustTick: Int = 0
    var onToggle: () -> Void
    var onWarmup: () -> Void
    var onDelete: () -> Void
    var onPlates: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button(set.isWarmup ? "Mark as Working Set" : "Mark as Warm-up", systemImage: "flame", action: onWarmup)
                if tracking == .weightReps {
                    Button("Plate Calculator", systemImage: "circle.grid.2x1", action: onPlates)
                }
                Button("Delete Set", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Text(set.isWarmup ? "W" : "\(number)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(set.isWarmup ? Theme.gold : .primary)
                    .frame(width: 30, height: 30)
                    .background((set.isWarmup ? Theme.gold.opacity(0.18) : Color.subtleFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            Button {
                fillFromPrevious()
            } label: {
                Text(previousText)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 76)
            }
            .buttonStyle(.plain)
            .disabled(previous == nil || set.isCompleted)

            switch tracking {
            case .weightReps, .bodyweight:
                SetNumberField(placeholder: tracking == .bodyweight ? "BW" : "0",
                               value: $set.weight, allowsDecimal: true,
                               focus: focus, field: .weight(set.id), isCompleted: set.isCompleted, adjustTick: adjustTick)
                    .frame(maxWidth: .infinity)
                SetNumberField(placeholder: "0",
                               value: Binding(get: { Double(set.reps) }, set: { set.reps = Int($0) }),
                               allowsDecimal: false, focus: focus, field: .reps(set.id), isCompleted: set.isCompleted, adjustTick: adjustTick)
                    .frame(width: 56)
            case .duration:
                SetNumberField(placeholder: "0",
                               value: Binding(get: { Double(set.seconds) }, set: { set.seconds = Int($0) }),
                               allowsDecimal: false, focus: focus, field: .seconds(set.id), isCompleted: set.isCompleted, adjustTick: adjustTick)
                    .frame(maxWidth: .infinity)
            }

            Button(action: onToggle) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(set.isCompleted ? AnyShapeStyle(Theme.success) : AnyShapeStyle(Color.subtleFill))
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(set.isCompleted ? .white : .secondary)
                }
                .frame(width: 38, height: 34)
                .overlay(alignment: .topTrailing) {
                    if set.prKind != nil {
                        Image(systemName: "trophy.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.gold, Color.black)
                            .offset(x: 6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .medium), trigger: set.isCompleted)
            .accessibilityLabel(set.isCompleted ? "Mark set incomplete" : "Complete set")
        }
        .padding(.vertical, 2)
        .animation(.snappy, value: set.prKind)
    }

    private var previousText: String {
        guard let previous else { return "—" }
        return ExerciseStats.setText(previous, tracking: tracking)
    }

    private func fillFromPrevious() {
        guard let previous else { return }
        set.weight = previous.weight
        set.reps = previous.reps
        set.seconds = previous.seconds
    }
}

/// Number field for set entry. Focusing it clears the text so typing replaces the value;
/// leaving it empty keeps the original value.
struct SetNumberField: View {
    let placeholder: String
    @Binding var value: Double
    var allowsDecimal: Bool
    var focus: FocusState<SetField?>.Binding
    let field: SetField
    var isCompleted: Bool
    var adjustTick: Int = 0

    @State private var text = ""
    @State private var original: Double = 0

    private var isFocused: Bool { focus.wrappedValue == field }

    var body: some View {
        TextField(isFocused && original != 0 ? format(original) : placeholder, text: $text)
            .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .font(.body.weight(.semibold).monospacedDigit())
            .focused(focus, equals: field)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isFocused ? Theme.ember.opacity(0.14) : (isCompleted ? Color.clear : Color.subtleFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isFocused ? Theme.ember : .clear, lineWidth: 1.5)
            )
            .onAppear { text = format(value) }
            .onChange(of: value) { _, newValue in
                // While typing, the text is the source of truth; external changes arrive via adjustTick.
                if !isFocused { text = format(newValue) }
            }
            .onChange(of: adjustTick) {
                if isFocused { text = format(value) }
            }
            .onChange(of: text) { _, newText in
                guard isFocused else { return }
                if newText.isEmpty {
                    value = original
                } else if let parsed = parse(newText) {
                    value = parsed
                }
            }
            .onChange(of: isFocused) { _, nowFocused in
                if nowFocused {
                    original = value
                    text = ""
                } else {
                    text = format(value)
                }
            }
    }

    private func parse(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(cleaned) else { return nil }
        return allowsDecimal ? v : v.rounded(.down)
    }

    private func format(_ v: Double) -> String {
        guard v != 0 else { return "" }
        return allowsDecimal ? Fmt.weight(v) : String(Int(v))
    }
}

// MARK: - Reorder

private struct ReorderExercisesSheet: View {
    @State var exercises: [SessionExercise]
    var onSave: ([SessionExercise]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(exercises) { ex in
                    HStack(spacing: 12) {
                        MuscleThumbnail(primary: ex.primaryMuscles, size: 36)
                        Text(ex.exerciseName)
                            .font(.body.weight(.semibold))
                    }
                }
                .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(exercises)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct PRBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .foregroundStyle(Theme.gold)
            Text(text)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(Theme.gold.opacity(0.25)), in: Capsule())
        .shadow(color: Theme.gold.opacity(0.3), radius: 12, y: 4)
    }
}


/// Number-entry controls shown above the keyboard while editing a set.
private struct EntryBar: View {
    let stepLabel: String
    var onMinus: () -> Void
    var onPlus: () -> Void
    var onNext: () -> Void
    var onDone: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            stepButton("minus", action: onMinus)
            Text(stepLabel)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 44)
            stepButton("plus", action: onPlus)
            Spacer()
            Button("Next", action: onNext)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Color.subtleFill, in: Capsule())
                .buttonStyle(.plain)
            Button(action: onDone) {
                Text("Done")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(Theme.accentGradient, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .frame(width: 44, height: 38)
                .background(Color.subtleFill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
