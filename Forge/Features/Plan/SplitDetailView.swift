import SwiftData
import SwiftUI

struct SplitDetailView: View {
    @Bindable var split: WorkoutSplit

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var days: [SplitDay] { split.orderedDays }

    var body: some View {
        List {
            Section {
                TextField("Split name", text: $split.name)
                    .font(.title3.weight(.bold))
                Picker("Schedule", selection: Binding(get: { split.scheduleMode }, set: { newValue in
                    withAnimation(.snappy) { split.scheduleMode = newValue }
                })) {
                    ForEach(ScheduleMode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
            } footer: {
                Text(split.scheduleMode.explanation)
            }

            Section {
                if split.isActive {
                    Label("This is your active split", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.ember)
                        .font(.subheadline.weight(.semibold))
                } else {
                    Button {
                        withAnimation(.snappy) { SplitService.activate(split, context: context) }
                    } label: {
                        Label("Set as Active Split", systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }

            if split.scheduleMode == .weekly {
                Section("Week at a Glance") {
                    WeekGlance(split: split)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }
            }

            Section {
                if days.isEmpty {
                    Text("Add your first day below.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    NavigationLink(value: day) {
                        DayRow(day: day, index: index, mode: split.scheduleMode,
                               isUpNext: split.scheduleMode == .rotation && index == ((split.rotationPosition % max(1, days.count)) + max(1, days.count)) % max(1, days.count))
                    }
                    .contextMenu {
                        if split.scheduleMode == .rotation {
                            Button("Do This Next", systemImage: "forward.end") {
                                SplitService.setNext(day, in: split)
                                try? context.save()
                            }
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(day) }
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(day) }
                    }
                }
                .onMove(perform: move)
                .onDelete { offsets in
                    offsets.map { days[$0] }.forEach(delete)
                }
            } header: {
                Text(split.scheduleMode == .rotation ? "Rotation Order" : "Workouts")
            } footer: {
                if split.scheduleMode == .rotation {
                    Text("Drag to reorder. Long-press a day to make it next. Rest days pass automatically after a day off.")
                }
            }

            Section {
                Button {
                    addDay(.workout)
                } label: {
                    Label("Add Workout Day", systemImage: "dumbbell.fill")
                }
                Button {
                    addDay(.cardio)
                } label: {
                    Label("Add Cardio Day", systemImage: "figure.run")
                }
                if split.scheduleMode == .rotation {
                    Button {
                        addDay(.rest)
                    } label: {
                        Label("Add Rest Day", systemImage: "moon.zzz.fill")
                    }
                }
            }
        }
        .navigationTitle(split.name.isEmpty ? "Split" : split.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Duplicate Split", systemImage: "plus.square.on.square") {
                        SplitService.duplicate(split, context: context)
                        try? context.save()
                    }
                    Button("Delete Split", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .confirmationDialog("Delete \(split.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Split", role: .destructive) {
                context.delete(split)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("Your workout history is kept.")
        }
        .onDisappear { try? context.save() }
    }

    private func addDay(_ kind: DayKind) {
        let count = days.count
        let name: String
        switch kind {
        case .workout: name = "Day \(days.filter { $0.kind == .workout }.count + 1)"
        case .cardio: name = "Run"
        case .rest: name = "Rest"
        }
        let day = SplitDay(name: name, kind: kind, order: count)
        context.insert(day)
        day.split = split
        if kind == .cardio { day.cardioDistance = 2 }
        try? context.save()
    }

    private func duplicate(_ day: SplitDay) {
        let copy = SplitDay(name: "\(day.name) Copy", kind: day.kind, order: days.count)
        context.insert(copy)
        copy.weekdays = []
        copy.includesCardio = day.includesCardio
        copy.cardioTypeRaw = day.cardioTypeRaw
        copy.cardioDistance = day.cardioDistance
        copy.split = split
        for ex in day.orderedExercises {
            let p = PlannedExercise(exerciseID: ex.exerciseID, name: ex.exerciseName, order: ex.order)
            context.insert(p)
            p.targetSets = ex.targetSets
            p.repLow = ex.repLow
            p.repHigh = ex.repHigh
            p.targetSeconds = ex.targetSeconds
            p.restSeconds = ex.restSeconds
            p.notes = ex.notes
            p.day = copy
        }
        try? context.save()
    }

    private func delete(_ day: SplitDay) {
        context.delete(day)
        SplitService.renumber(days.filter { $0.id != day.id })
        try? context.save()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = days
        let current = split.scheduleMode == .rotation && !ordered.isEmpty ? ordered[split.rotationPosition % ordered.count] : nil
        ordered.move(fromOffsets: source, toOffset: destination)
        SplitService.renumber(ordered)
        if let current, let newIndex = ordered.firstIndex(where: { $0.id == current.id }) {
            split.rotationPosition = newIndex
        }
        try? context.save()
    }
}

private struct DayRow: View {
    let day: SplitDay
    let index: Int
    let mode: ScheduleMode
    var isUpNext = false

    var body: some View {
        HStack(spacing: 12) {
            if mode == .rotation {
                Text("\(index + 1)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            IconBadge(systemName: day.kind.symbol, gradient: gradient, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(day.displayName)
                        .font(.body.weight(.semibold))
                    if isUpNext {
                        Text("UP NEXT")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(.white)
                            .background(Theme.accentGradient, in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var gradient: LinearGradient {
        switch day.kind {
        case .workout: Theme.accentGradient
        case .cardio: Theme.cardioGradient
        case .rest: Theme.restGradient
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if mode == .weekly {
            parts.append(day.weekdays.isEmpty ? "Not scheduled" : day.weekdays.sorted().map { ScheduleEngine.shortName(forWeekday: $0) }.joined(separator: ", "))
        }
        switch day.kind {
        case .workout:
            let count = day.orderedExercises.count
            parts.append(count == 1 ? "1 exercise" : "\(count) exercises")
            if day.includesCardio { parts.append("+ \(Fmt.miles(day.cardioDistance)) mi run") }
        case .cardio:
            parts.append("\(Fmt.miles(day.cardioDistance)) mi · \(day.cardioType.displayName)")
        case .rest:
            parts.append("Recovery")
        }
        return parts.joined(separator: " · ")
    }
}

/// Seven columns showing what's scheduled each weekday.
private struct WeekGlance: View {
    let split: WorkoutSplit

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(ScheduleEngine.orderedWeekdays(), id: \.self) { weekday in
                let days = split.orderedDays.filter { $0.weekdays.contains(weekday) }
                let isToday = Calendar.current.component(.weekday, from: .now) == weekday
                VStack(spacing: 6) {
                    Text(ScheduleEngine.shortName(forWeekday: weekday).uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isToday ? Theme.ember : .secondary)
                    if days.isEmpty {
                        Image(systemName: "moon.zzz")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.subtleFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        ForEach(days) { day in
                            VStack(spacing: 3) {
                                Image(systemName: day.kind.symbol)
                                    .font(.caption)
                                Text(day.displayName)
                                    .font(.system(size: 9, weight: .semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 2)
                            .background(day.kind == .cardio ? Theme.cardioGradient : Theme.accentGradient,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
