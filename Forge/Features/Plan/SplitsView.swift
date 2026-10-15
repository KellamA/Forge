import SwiftData
import SwiftUI

struct SplitsView: View {
    @Environment(\.modelContext) private var context
    @Environment(ExerciseLibrary.self) private var library
    @Query(sort: \WorkoutSplit.createdAt) private var splits: [WorkoutSplit]
    @State private var showingNewSplit = false
    @State private var previewTemplate: SplitTemplate?
    @State private var path = NavigationPath()

    private var active: WorkoutSplit? { splits.first(where: \.isActive) }
    private var others: [WorkoutSplit] { splits.filter { !$0.isActive } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 20) {
                    if let active {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Active Split")
                            NavigationLink(value: active) {
                                ActiveSplitCard(split: active)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    } else if splits.isEmpty {
                        EmptyStateCard(icon: "calendar.badge.plus",
                                       title: "Build your training split",
                                       message: "Pin workouts to days of the week, or set up a rotation like Push → Pull → Legs that picks up wherever you left off.",
                                       actionTitle: "Create a Split") { showingNewSplit = true }
                    }

                    if !others.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(active == nil ? "Your Splits" : "Other Splits")
                            ForEach(others) { split in
                                NavigationLink(value: split) {
                                    SplitRowCard(split: split)
                                }
                                .buttonStyle(PressableStyle())
                                .contextMenu {
                                    Button("Set as Active", systemImage: "checkmark.circle") {
                                        withAnimation(.snappy) { SplitService.activate(split, context: context) }
                                    }
                                    Button("Duplicate", systemImage: "plus.square.on.square") {
                                        SplitService.duplicate(split, context: context)
                                        try? context.save()
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        context.delete(split)
                                        try? context.save()
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Templates", subtitle: "Start from a proven program and make it yours.")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(SplitTemplate.all) { template in
                                    Button {
                                        previewTemplate = template
                                    } label: {
                                        TemplateCard(template: template)
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.horizontal, -16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .navigationTitle("Plan")
            .navigationDestination(for: WorkoutSplit.self) { split in
                SplitDetailView(split: split)
            }
            .navigationDestination(for: SplitDay.self) { day in
                DayEditorView(day: day)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewSplit = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Split")
                }
            }
            .sheet(isPresented: $showingNewSplit) {
                NewSplitSheet { split in
                    path.append(split)
                }
            }
            .sheet(item: $previewTemplate) { template in
                TemplatePreviewSheet(template: template) { split in
                    path.append(split)
                }
            }
        }
    }
}

// MARK: - Cards

struct ActiveSplitCard: View {
    let split: WorkoutSplit

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("ACTIVE", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(split.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(split.scheduleMode.displayName) · \(split.trainingDays.count) training days")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            SplitScheduleStrip(split: split, onDark: true)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: Theme.ember.opacity(0.3), radius: 16, y: 8)
    }
}

struct SplitRowCard: View {
    let split: WorkoutSplit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(split.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(split.scheduleMode.displayName) · \(split.trainingDays.count) training days")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            SplitScheduleStrip(split: split, onDark: false)
        }
        .cardStyle()
    }
}

/// Weekly: seven day columns. Rotation: ordered pills.
struct SplitScheduleStrip: View {
    let split: WorkoutSplit
    var onDark = false

    var body: some View {
        switch split.scheduleMode {
        case .weekly:
            HStack(spacing: 6) {
                ForEach(ScheduleEngine.orderedWeekdays(), id: \.self) { weekday in
                    let days = split.orderedDays.filter { $0.weekdays.contains(weekday) && $0.kind != .rest }
                    VStack(spacing: 5) {
                        Text(ScheduleEngine.letter(forWeekday: weekday))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(onDark ? .white.opacity(0.75) : .secondary)
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(days.isEmpty ? (onDark ? Color.white.opacity(0.15) : Color.subtleFill)
                                      : (onDark ? .white : (days.first?.kind == .cardio ? Theme.cardio : Theme.ember)))
                            if let first = days.first {
                                Image(systemName: first.kind == .cardio ? "figure.run" : "dumbbell.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(onDark ? (first.kind == .cardio ? Theme.cardio : Theme.ember) : .white)
                            }
                        }
                        .frame(height: 30)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        case .rotation:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(split.orderedDays.enumerated()), id: \.element.id) { index, day in
                        HStack(spacing: 4) {
                            Image(systemName: day.kind.symbol)
                                .font(.caption2)
                            Text(day.displayName)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(onDark ? (index == split.rotationPosition % max(1, split.orderedDays.count) ? Theme.ember : .white) : .primary)
                        .background(onDark ? (index == split.rotationPosition % max(1, split.orderedDays.count) ? Color.white : Color.white.opacity(0.18)) : Color.subtleFill,
                                    in: Capsule())
                        if index < split.orderedDays.count - 1 {
                            Image(systemName: "arrow.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(onDark ? .white.opacity(0.6) : .secondary)
                        }
                    }
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(onDark ? .white.opacity(0.6) : .secondary)
                }
            }
        }
    }
}

struct TemplateCard: View {
    let template: SplitTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconBadge(systemName: template.icon, size: 40)
            Text(template.name)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(template.daysPerWeek)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ember)
            Text(template.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .frame(width: 190, alignment: .leading)
        .cardStyle(padding: 16)
    }
}

// MARK: - Sheets

struct TemplatePreviewSheet: View {
    let template: SplitTemplate
    var onCreate: (WorkoutSplit) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ExerciseLibrary.self) private var library
    @State private var makeActive = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        IconBadge(systemName: template.icon, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.name).font(.title2.weight(.bold))
                            Text("\(template.mode.displayName) · \(template.daysPerWeek)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(template.summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    ForEach(Array(template.days.enumerated()), id: \.offset) { _, day in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: day.kind.symbol)
                                    .foregroundStyle(day.kind == .cardio ? Theme.cardio : Theme.ember)
                                Text(day.name).font(.headline)
                                Spacer()
                                if !day.weekdays.isEmpty {
                                    Text(day.weekdays.sorted().map { ScheduleEngine.shortName(forWeekday: $0) }.joined(separator: ", "))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let (type, miles) = day.cardio {
                                Text("\(Fmt.miles(miles)) mi · \(type.displayName)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(day.lifts, id: \.id) { lift in
                                HStack {
                                    Text(library.exercise(id: lift.id)?.name ?? lift.id)
                                        .font(.subheadline)
                                    Spacer()
                                    Text(lift.low == lift.high ? "\(lift.sets) × \(lift.low)" : "\(lift.sets) × \(lift.low)–\(lift.high)")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .cardStyle()
                    }
                    Toggle("Make this my active split", isOn: $makeActive)
                        .padding(.horizontal, 4)
                        .tint(Theme.ember)
                }
                .padding(16)
            }
            .screenBackground()
            .safeAreaInset(edge: .bottom) {
                Button("Use This Template") {
                    let split = template.instantiate(in: context, library: library, activate: makeActive)
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onCreate(split) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct NewSplitSheet: View {
    var onCreate: (WorkoutSplit) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var splits: [WorkoutSplit]
    @State private var name = ""
    @State private var mode: ScheduleMode = .weekly

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Split name (e.g. Summer Cut)", text: $name)
                        .font(.headline)
                }
                Section {
                    ForEach(ScheduleMode.allCases) { option in
                        Button {
                            withAnimation(.snappy) { mode = option }
                        } label: {
                            HStack(spacing: 14) {
                                IconBadge(systemName: option == .weekly ? "calendar" : "arrow.triangle.2.circlepath",
                                          gradient: mode == option ? Theme.accentGradient : LinearGradient(colors: [.gray.opacity(0.5)], startPoint: .top, endPoint: .bottom),
                                          size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(option.explanation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: mode == option ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(mode == option ? Theme.ember : .secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Schedule")
                }
            }
            .navigationTitle("New Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let split = WorkoutSplit(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "My Split" : name, mode: mode)
                        context.insert(split)
                        if splits.allSatisfy({ !$0.isActive }) { split.isActive = true }
                        try? context.save()
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onCreate(split) }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
