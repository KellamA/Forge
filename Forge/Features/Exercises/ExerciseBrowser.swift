import SwiftData
import SwiftUI

/// Searchable, filterable exercise list used by the library tab and the picker.
struct ExerciseBrowser: View {
    enum Mode {
        case browse
        case pick
    }

    let mode: Mode
    var selectedIDs: Set<String> = []
    var onSelect: (ExerciseInfo) -> Void = { _ in }

    @Environment(ExerciseLibrary.self) private var library
    @Query private var favoriteRecords: [FavoriteExercise]
    @State private var filter = ExerciseFilter()
    @State private var showingFilters = false
    @State private var showingNewExercise = false

    private var favorites: Set<String> { Set(favoriteRecords.map(\.exerciseID)) }

    var body: some View {
        let results = library.search(filter, favorites: favorites)
        List {
            Section {
                muscleChips
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if filter.isActive {
                Section {
                    if results.isEmpty {
                        noResults
                    }
                    ForEach(results) { row($0) }
                } header: {
                    Text(results.count == 1 ? "1 exercise" : "\(results.count) exercises")
                }
            } else {
                if !library.custom.isEmpty {
                    Section("My Exercises") {
                        ForEach(library.custom) { row($0) }
                    }
                }
                let favs = library.all.filter { favorites.contains($0.id) }
                if !favs.isEmpty {
                    Section("Favorites") {
                        ForEach(favs) { row($0) }
                    }
                }
                Section("Popular") {
                    ForEach(library.all.filter(\.isPopular)) { row($0) }
                }
                Section("All Exercises · \(library.all.count)") {
                    ForEach(library.all) { row($0) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $filter.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search \(library.all.count) exercises")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle(isOn: $filter.favoritesOnly) { Label("Favorites Only", systemImage: "star") }
                    Toggle(isOn: $filter.customOnly) { Label("My Exercises Only", systemImage: "person") }
                    Menu("Equipment") {
                        ForEach(Equipment.allCases) { eq in
                            Toggle(isOn: binding(for: eq)) { Label(eq.displayName, systemImage: eq.symbol) }
                        }
                    }
                    Menu("Type") {
                        ForEach(ExerciseCategory.allCases) { cat in
                            Toggle(cat.displayName, isOn: binding(for: cat))
                        }
                    }
                    if filter.isActive {
                        Divider()
                        Button("Clear Filters", role: .destructive) { filter = ExerciseFilter() }
                    }
                } label: {
                    Image(systemName: filter.equipment.isEmpty && filter.categories.isEmpty && !filter.favoritesOnly && !filter.customOnly
                          ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewExercise = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Custom Exercise")
            }
        }
        .sheet(isPresented: $showingNewExercise) {
            CustomExerciseEditor(existing: nil) { created in
                if mode == .pick { onSelect(created) }
            }
        }
    }

    @ViewBuilder
    private func row(_ info: ExerciseInfo) -> some View {
        switch mode {
        case .browse:
            NavigationLink(value: info) {
                ExerciseRow(info: info, isFavorite: favorites.contains(info.id))
            }
        case .pick:
            Button {
                onSelect(info)
            } label: {
                HStack {
                    ExerciseRow(info: info, isFavorite: favorites.contains(info.id))
                    Image(systemName: selectedIDs.contains(info.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(selectedIDs.contains(info.id) ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.secondary.opacity(0.4)))
                        .contentTransition(.symbolEffect(.replace))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: selectedIDs.contains(info.id))
        }
    }

    private var muscleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: filter.muscles.isEmpty) {
                    withAnimation(.snappy) { filter.muscles = [] }
                }
                ForEach(Muscle.displayOrder) { muscle in
                    FilterChip(title: muscle.displayName, isSelected: filter.muscles.contains(muscle)) {
                        withAnimation(.snappy) {
                            if filter.muscles.contains(muscle) { filter.muscles.remove(muscle) } else { filter.muscles.insert(muscle) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No matches")
                .font(.headline)
            Text("Try a different search, or create a custom exercise.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Create “\(filter.query.isEmpty ? "New Exercise" : filter.query)”") {
                showingNewExercise = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func binding(for eq: Equipment) -> Binding<Bool> {
        Binding(get: { filter.equipment.contains(eq) },
                set: { if $0 { filter.equipment.insert(eq) } else { filter.equipment.remove(eq) } })
    }

    private func binding(for cat: ExerciseCategory) -> Binding<Bool> {
        Binding(get: { filter.categories.contains(cat) },
                set: { if $0 { filter.categories.insert(cat) } else { filter.categories.remove(cat) } })
    }
}

struct ExerciseRow: View {
    let info: ExerciseInfo
    var isFavorite = false

    var body: some View {
        HStack(spacing: 12) {
            MuscleThumbnail(primary: info.primary, secondary: info.secondary, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(info.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.gold)
                    }
                }
                Text(info.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

/// Multi-select exercise picker presented as a sheet.
struct ExercisePickerView: View {
    var title = "Add Exercises"
    var allowsMultiple = true
    let onDone: ([ExerciseInfo]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: [ExerciseInfo] = []

    var body: some View {
        NavigationStack {
            ExerciseBrowser(mode: .pick, selectedIDs: Set(selected.map(\.id))) { info in
                if !allowsMultiple {
                    onDone([info])
                    dismiss()
                    return
                }
                if let i = selected.firstIndex(where: { $0.id == info.id }) {
                    selected.remove(at: i)
                } else {
                    selected.append(info)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if allowsMultiple && !selected.isEmpty {
                    Button {
                        onDone(selected)
                        dismiss()
                    } label: {
                        Text(selected.count == 1 ? "Add 1 Exercise" : "Add \(selected.count) Exercises")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: selected.isEmpty)
        }
    }
}

struct ExerciseLibraryView: View {
    @Environment(ExerciseLibrary.self) private var library

    var body: some View {
        NavigationStack {
            ExerciseBrowser(mode: .browse)
                .navigationTitle("Exercises")
                .navigationDestination(for: ExerciseInfo.self) { info in
                    ExerciseDetailView(exerciseID: info.id)
                }
        }
    }
}
