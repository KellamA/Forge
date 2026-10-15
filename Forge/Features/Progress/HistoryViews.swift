import SwiftData
import SwiftUI

// MARK: - History

struct HistoryView: View {
    @Environment(HistoryStore.self) private var history
    @Environment(\.modelContext) private var context
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @State private var selectedDay: Date?
    @State private var pendingDelete: HistorySnapshot.SessionEntry?

    private var snapshot: HistorySnapshot { history.snapshot }

    var body: some View {
        let calendar = Calendar.current
        let filtered = snapshot.sessions.filter { s in
            if let selectedDay { return calendar.isDate(s.start, inSameDayAs: selectedDay) }
            return true
        }
        let cardio = snapshot.cardio.filter { c in
            guard !c.isPartOfWorkout else { return false }
            if let selectedDay { return calendar.isDate(c.date, inSameDayAs: selectedDay) }
            return true
        }
        let groups = Dictionary(grouping: filtered) { calendar.dateInterval(of: .month, for: $0.start)!.start }
        List {
            Section {
                MonthCalendar(month: $month, selectedDay: $selectedDay,
                              liftDays: Set(snapshot.sessions.map { calendar.startOfDay(for: $0.start) }),
                              cardioDays: Set(snapshot.cardio.map { calendar.startOfDay(for: $0.date) }))
            }
            if let selectedDay {
                Section {
                    Button("Show all workouts") { withAnimation(.snappy) { self.selectedDay = nil } }
                } header: {
                    Text(selectedDay.formatted(.dateTime.weekday(.wide).month().day()))
                }
            }
            ForEach(groups.keys.sorted(by: >), id: \.self) { monthStart in
                Section(monthStart.formatted(.dateTime.month(.wide).year())) {
                    ForEach(groups[monthStart]!) { session in
                        NavigationLink(value: SessionLink(id: session.modelID)) {
                            HistoryRow(session: session)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { pendingDelete = session }
                        }
                    }
                }
            }
            if !cardio.isEmpty {
                Section("Runs") {
                    ForEach(cardio.prefix(selectedDay == nil ? 30 : 100)) { run in
                        HStack(spacing: 12) {
                            Image(systemName: run.type.symbol)
                                .foregroundStyle(Theme.cardio)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Fmt.miles(run.distance)) mi \(run.type.displayName)")
                                    .font(.subheadline.weight(.semibold))
                                Text(run.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let pace = run.pace {
                                Text(Fmt.pace(pace))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { deleteRun(run.id) }
                        }
                    }
                }
            }
            if filtered.isEmpty && cardio.isEmpty {
                Section {
                    Text(selectedDay == nil ? "No workouts yet." : "Nothing logged this day.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("History")
        .confirmationDialog("Delete this workout?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                if let entry = pendingDelete, let model = context.model(for: entry.modelID) as? WorkoutSession {
                    context.delete(model)
                    try? context.save()
                    PRService.recomputeAll(context: context)
                }
                pendingDelete = nil
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func deleteRun(_ id: UUID) {
        let descriptor = FetchDescriptor<CardioLog>(predicate: #Predicate { $0.id == id })
        if let log = try? context.fetch(descriptor).first {
            context.delete(log)
            try? context.save()
        }
    }
}

private struct HistoryRow: View {
    let session: HistorySnapshot.SessionEntry

    var body: some View {
        HStack(spacing: 12) {
            MuscleThumbnail(primary: session.muscles, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.name)
                        .font(.body.weight(.semibold))
                    if session.prCount > 0 {
                        Label("\(session.prCount)", systemImage: "trophy.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.gold)
                    }
                }
                Text("\(session.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(Fmt.duration(session.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Fmt.volume(session.volume)) lb · \(session.workingSets) sets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct MonthCalendar: View {
    @Binding var month: Date
    @Binding var selectedDay: Date?
    let liftDays: Set<Date>
    let cardioDays: Set<Date>

    var body: some View {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: month)!
        let firstWeekday = calendar.component(.weekday, from: month)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: leading) + range.map { calendar.date(byAdding: .day, value: $0 - 1, to: month)! }
        VStack(spacing: 12) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
            }
            .buttonStyle(.borderless)
            .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(ScheduleEngine.orderedWeekdays(), id: \.self) { weekday in
                    Text(ScheduleEngine.letter(forWeekday: weekday))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let lifted = liftDays.contains(date)
                        let ran = cardioDays.contains(date)
                        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                        Button {
                            withAnimation(.snappy) { selectedDay = isSelected ? nil : date }
                        } label: {
                            VStack(spacing: 3) {
                                Text(date.formatted(.dateTime.day()))
                                    .font(.subheadline.weight(lifted || ran ? .bold : .regular).monospacedDigit())
                                    .foregroundStyle(lifted ? .white : (calendar.isDateInToday(date) ? Theme.ember : .primary))
                                    .frame(width: 34, height: 34)
                                    .background {
                                        if lifted {
                                            Circle().fill(Theme.accentGradient)
                                        } else if isSelected {
                                            Circle().fill(Color.subtleFill)
                                        }
                                    }
                                    .overlay(Circle().stroke(isSelected ? Theme.ember : .clear, lineWidth: 2).padding(-2))
                                Circle()
                                    .fill(ran ? Theme.cardio : .clear)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func shift(_ months: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: months, to: month) {
            withAnimation(.snappy) {
                month = next
                selectedDay = nil
            }
        }
    }
}

// MARK: - Session detail

struct SessionDetailView: View {
    let sessionID: PersistentIdentifier

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var confirmDelete = false

    var body: some View {
        if let session = context.model(for: sessionID) as? WorkoutSession, !session.isDeleted {
            SessionDetailContent(session: session, isEditing: $isEditing) {
                confirmDelete = true
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Done" : "Edit") {
                        if isEditing {
                            try? context.save()
                            PRService.recomputeAll(context: context)
                        }
                        withAnimation(.snappy) { isEditing.toggle() }
                    }
                    .fontWeight(isEditing ? .semibold : .regular)
                }
            }
            .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Workout", role: .destructive) {
                    context.delete(session)
                    try? context.save()
                    PRService.recomputeAll(context: context)
                    dismiss()
                }
            }
        } else {
            ContentUnavailableView("Workout not found", systemImage: "questionmark.circle")
        }
    }
}

private struct SessionDetailContent: View {
    @Bindable var session: WorkoutSession
    @Binding var isEditing: Bool
    var onDelete: () -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    if isEditing {
                        TextField("Name", text: $session.name)
                            .font(.title2.weight(.bold))
                        DatePicker("Started", selection: Binding(get: { session.startedAt }, set: { newStart in
                            let duration = session.duration
                            session.startedAt = newStart
                            session.endedAt = newStart.addingTimeInterval(duration)
                        }))
                    } else {
                        Text(session.name)
                            .font(.title2.weight(.bold))
                        Text(session.startedAt.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        pill(Fmt.duration(session.duration), "timer")
                        pill("\(Fmt.volume(session.totalVolume)) lb", "scalemass.fill")
                        pill("\(session.workingSetCount) sets", "square.stack.3d.up.fill")
                    }
                    if session.rating > 0 {
                        Text("Felt: " + ["😮‍💨", "😕", "🙂", "💪", "🔥"][min(4, session.rating - 1)])
                            .font(.subheadline)
                    }
                    if !session.muscles.isEmpty {
                        BodyMapView(intensities: Dictionary(uniqueKeysWithValues: session.muscles.map { ($0, 1.0) }), spacing: 24)
                            .frame(height: 170)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 6)
            }

            ForEach(session.orderedExercises) { ex in
                Section {
                    ForEach(ex.orderedSets) { set in
                        SessionSetRow(set: set, tracking: ex.tracking, isEditing: isEditing)
                    }
                    .onDelete { offsets in
                        offsets.map { ex.orderedSets[$0] }.forEach { context.delete($0) }
                    }
                } header: {
                    HStack {
                        Text(ex.exerciseName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .textCase(nil)
                        Spacer()
                        if ex.volume > 0 {
                            Text("\(Fmt.volume(ex.volume)) lb")
                                .font(.caption.monospacedDigit())
                                .textCase(nil)
                        }
                    }
                }
            }

            ForEach(session.cardio ?? []) { log in
                Section("Cardio") {
                    HStack {
                        Label("\(Fmt.miles(log.distance)) mi \(log.type.displayName)", systemImage: log.type.symbol)
                        Spacer()
                        if let pace = log.pace { Text(Fmt.pace(pace)).foregroundStyle(.secondary) }
                    }
                }
            }

            if isEditing || !session.notes.isEmpty {
                Section("Notes") {
                    if isEditing {
                        TextField("Notes", text: $session.notes, axis: .vertical)
                    } else {
                        Text(session.notes)
                    }
                }
            }

            if isEditing {
                Section {
                    Button("Delete Workout", role: .destructive, action: onDelete)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pill(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.subtleFill, in: Capsule())
    }
}

private struct SessionSetRow: View {
    @Bindable var set: SetLog
    let tracking: TrackingType
    let isEditing: Bool

    var body: some View {
        HStack {
            Text(set.isWarmup ? "W" : "\(set.order + 1)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(set.isWarmup ? Theme.gold : .secondary)
                .frame(width: 24)
            if isEditing {
                switch tracking {
                case .weightReps, .bodyweight:
                    NumericField(placeholder: "lb", value: $set.weight)
                        .padding(6)
                        .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 8))
                    Text("×").foregroundStyle(.secondary)
                    NumericField(placeholder: "reps", value: Binding(get: { Double(set.reps) }, set: { set.reps = Int($0) }), allowsDecimal: false)
                        .padding(6)
                        .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 8))
                case .duration:
                    NumericField(placeholder: "sec", value: Binding(get: { Double(set.seconds) }, set: { set.seconds = Int($0) }), allowsDecimal: false)
                        .padding(6)
                        .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Text(text)
                    .font(.body.monospacedDigit())
                Spacer()
                if let pr = set.prKind {
                    Label(pr.label, systemImage: "trophy.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.gold)
                } else if tracking == .weightReps, let e = OneRepMax.estimate(weight: set.weight, reps: set.reps, formula: .current), !set.isWarmup {
                    Text("e1RM \(Fmt.weight(e.rounded()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var text: String {
        switch tracking {
        case .weightReps: "\(Fmt.weight(set.weight)) lb × \(set.reps)"
        case .bodyweight: set.weight > 0 ? "BW +\(Fmt.weight(set.weight)) lb × \(set.reps)" : "\(set.reps) reps"
        case .duration: "\(set.seconds) sec"
        }
    }
}

// MARK: - Records

struct RecordsView: View {
    @Environment(HistoryStore.self) private var history
    @State private var query = ""

    var body: some View {
        let records = history.snapshot.records().filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        List(records) { record in
            NavigationLink(value: ExerciseLink(id: record.exerciseID)) {
                HStack(spacing: 12) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(Theme.gold)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.name)
                            .font(.body.weight(.semibold))
                        Text("\(record.detail) · \(record.date.formatted(.dateTime.month(.abbreviated).day().year()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Fmt.weight(record.value.rounded()))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Theme.accentGradient)
                        Text(record.tracking == .weightReps ? "lb e1RM" : HistorySnapshot.unit(for: record.tracking))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .searchable(text: $query, prompt: "Search records")
        .navigationTitle("Personal Records")
        .overlay {
            if records.isEmpty {
                ContentUnavailableView("No records yet", systemImage: "trophy", description: Text("Finish a workout to set your first records."))
            }
        }
    }
}
