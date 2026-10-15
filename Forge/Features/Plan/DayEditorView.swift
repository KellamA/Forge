import SwiftData
import SwiftUI

struct DayEditorView: View {
    @Bindable var day: SplitDay

    @Environment(\.modelContext) private var context
    @Environment(ExerciseLibrary.self) private var library
    @Environment(WorkoutManager.self) private var workout
    @State private var showingPicker = false
    @State private var editing: PlannedExercise?

    private var exercises: [PlannedExercise] { day.orderedExercises }
    private var isWeekly: Bool { day.split?.scheduleMode == .weekly }

    var body: some View {
        List {
            Section {
                TextField("Day name", text: $day.name)
                    .font(.title3.weight(.bold))
                if day.kind != .rest {
                    Picker("Type", selection: Binding(get: { day.kind }, set: { newValue in withAnimation(.snappy) { day.kind = newValue } })) {
                        Text("Workout").tag(DayKind.workout)
                        Text("Cardio").tag(DayKind.cardio)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }
            }

            if isWeekly {
                Section {
                    WeekdayPicker(selection: $day.weekdays)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                } header: {
                    Text("Scheduled On")
                } footer: {
                    if day.weekdays.isEmpty {
                        Text("Pick at least one day so it shows up on your Today screen.")
                    }
                }
            }

            switch day.kind {
            case .workout:
                workoutSections
            case .cardio:
                cardioSection(isFinisher: false)
            case .rest:
                Section {
                    Label("Rest days in a rotation pass automatically once a day goes by without training.", systemImage: "moon.zzz.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(day.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if day.kind == .workout && !exercises.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { picked in add(picked) }
        }
        .sheet(item: $editing) { planned in
            PlannedExerciseEditor(planned: planned)
                .presentationDetents([.medium, .large])
        }
        .onDisappear { try? context.save() }
    }

    @ViewBuilder
    private var workoutSections: some View {
        if !exercises.isEmpty {
            Section {
                VStack(spacing: 10) {
                    BodyMapView(intensities: muscleIntensities, spacing: 28)
                        .frame(height: 190)
                    HStack(spacing: 16) {
                        Label("\(exercises.count) exercises", systemImage: "list.bullet")
                        Label("\(exercises.reduce(0) { $0 + $1.targetSets }) sets", systemImage: "square.stack.3d.up")
                        Label("~\(day.estimatedMinutes) min", systemImage: "clock")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }

        Section {
            ForEach(exercises) { planned in
                Button {
                    editing = planned
                } label: {
                    PlannedExerciseRow(planned: planned, info: library.exercise(id: planned.exerciseID))
                }
                .buttonStyle(.plain)
            }
            .onMove(perform: move)
            .onDelete { offsets in
                offsets.map { exercises[$0] }.forEach { context.delete($0) }
                SplitService.renumberExercises(exercises.filter { ex in !offsets.map { exercises[$0].id }.contains(ex.id) })
            }
            Button {
                showingPicker = true
            } label: {
                Label("Add Exercises", systemImage: "plus.circle.fill")
                    .font(.body.weight(.semibold))
            }
        } header: {
            Text("Exercises")
        } footer: {
            if !exercises.isEmpty {
                Text("Tap an exercise to set sets, rep range and rest.")
            }
        }

        Section {
            Toggle(isOn: $day.includesCardio.animation(.snappy)) {
                Label("Add a run after lifting", systemImage: "figure.run")
            }
            .tint(Theme.cardio)
            if day.includesCardio {
                cardioControls
            }
        } header: {
            Text("Cardio Finisher")
        }

        if workout.activeSession == nil && !exercises.isEmpty {
            Section {
                Button {
                    workout.start(day: day)
                } label: {
                    Label("Start This Workout Now", systemImage: "play.fill")
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func cardioSection(isFinisher: Bool) -> some View {
        Section("Cardio") {
            cardioControls
        }
    }

    @ViewBuilder
    private var cardioControls: some View {
        Picker("Type", selection: Binding(get: { day.cardioType }, set: { day.cardioType = $0 })) {
            ForEach(CardioType.allCases) { type in
                Label(type.displayName, systemImage: type.symbol).tag(type)
            }
        }
        .pickerStyle(.segmented)
        DistanceStepper(miles: $day.cardioDistance, showsLaps: day.cardioType == .track)
    }

    private var muscleIntensities: [Muscle: Double] {
        var sets: [Muscle: Double] = [:]
        for planned in exercises {
            guard let info = library.exercise(id: planned.exerciseID) else { continue }
            for m in info.primary { sets[m, default: 0] += Double(planned.targetSets) }
            for m in info.secondary { sets[m, default: 0] += Double(planned.targetSets) * 0.5 }
        }
        let maxSets = sets.values.max() ?? 1
        return sets.mapValues { 0.35 + 0.65 * ($0 / maxSets) }
    }

    private func add(_ infos: [ExerciseInfo]) {
        var order = (exercises.map(\.order).max() ?? -1) + 1
        for info in infos {
            let planned = PlannedExercise(exercise: info, order: order)
            context.insert(planned)
            planned.day = day
            order += 1
        }
        try? context.save()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = exercises
        ordered.move(fromOffsets: source, toOffset: destination)
        SplitService.renumberExercises(ordered)
        try? context.save()
    }
}

extension SplitService {
    static func renumberExercises(_ exercises: [PlannedExercise]) {
        for (i, ex) in exercises.enumerated() where ex.order != i { ex.order = i }
    }
}

private struct PlannedExerciseRow: View {
    let planned: PlannedExercise
    let info: ExerciseInfo?

    var body: some View {
        HStack(spacing: 12) {
            MuscleThumbnail(primary: info?.primary ?? [], secondary: info?.secondary ?? [], size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(planned.exerciseName)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(info?.tracking == .duration ? "\(planned.targetSets) × \(planned.targetSeconds)s" : "\(planned.targetSets) × \(planned.repRangeText)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.ember)
                    Label(Fmt.restLabel(planned.restSeconds), systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !planned.notes.isEmpty {
                    Text(planned.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct WeekdayPicker: View {
    @Binding var selection: [Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ScheduleEngine.orderedWeekdays(), id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    withAnimation(.snappy) {
                        if isOn { selection.removeAll { $0 == weekday } } else { selection.append(weekday) }
                    }
                } label: {
                    Text(ScheduleEngine.shortName(forWeekday: weekday))
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(isOn ? .white : .primary)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accentGradient)
                            } else {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.subtleFill)
                            }
                        }
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: isOn)
            }
        }
    }
}

struct DistanceStepper: View {
    @Binding var miles: Double
    var showsLaps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Distance")
                Spacer()
                HStack(spacing: 0) {
                    button("minus") { miles = max(0.25, ((miles - 0.25) * 4).rounded() / 4) }
                    Text("\(Fmt.miles(miles)) mi")
                        .font(.body.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 76)
                        .contentTransition(.numericText(value: miles))
                    button("plus") { miles = min(50, ((miles + 0.25) * 4).rounded() / 4) }
                }
                .background(Color.subtleFill, in: Capsule())
            }
            if showsLaps {
                Text("≈ \(Int((miles / CardioType.milesPerLap).rounded())) laps of a 400 m track")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy, value: miles)
    }

    private func button(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .frame(width: 46, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: miles)
    }
}

struct PlannedExerciseEditor: View {
    @Bindable var planned: PlannedExercise

    @Environment(\.dismiss) private var dismiss
    @Environment(ExerciseLibrary.self) private var library
    @Environment(\.modelContext) private var context
    @State private var showingDetail = false

    private var info: ExerciseInfo? { library.exercise(id: planned.exerciseID) }
    private static let restOptions = [0, 30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240, 300]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        MuscleThumbnail(primary: info?.primary ?? [], secondary: info?.secondary ?? [], size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(planned.exerciseName).font(.headline)
                            if let info { Text(info.subtitle).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Section("Target") {
                    ValueStepper(title: "Sets", value: $planned.targetSets, range: 1...12)
                    if info?.tracking == .duration {
                        ValueStepper(title: "Seconds", value: $planned.targetSeconds, range: 5...600, step: 5) { "\($0)s" }
                    } else {
                        ValueStepper(title: "Min Reps", value: Binding(get: { planned.repLow }, set: { v in
                            planned.repLow = v
                            if planned.repHigh < v { planned.repHigh = v }
                        }), range: 1...50)
                        ValueStepper(title: "Max Reps", value: Binding(get: { planned.repHigh }, set: { v in
                            planned.repHigh = v
                            if planned.repLow > v { planned.repLow = v }
                        }), range: 1...50)
                    }
                }
                Section {
                    Picker("Rest Between Sets", selection: $planned.restSeconds) {
                        ForEach(Self.restOptions, id: \.self) { s in
                            Text(s == 0 ? "None" : Fmt.restLabel(s)).tag(s)
                        }
                    }
                } footer: {
                    Text("When you hit the top of the rep range on every set, Forge suggests adding weight next time.")
                }
                Section("Notes") {
                    TextField("Seat height, grip, tempo…", text: $planned.notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("Edit Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
