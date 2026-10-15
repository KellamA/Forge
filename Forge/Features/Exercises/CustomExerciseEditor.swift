import SwiftData
import SwiftUI

/// Create or edit a custom exercise. Muscles are picked by tapping the body map.
struct CustomExerciseEditor: View {
    let existing: CustomExercise?
    var onCreate: ((ExerciseInfo) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ExerciseLibrary.self) private var library
    @Query private var allCustom: [CustomExercise]

    @State private var name = ""
    @State private var primary: Set<Muscle> = []
    @State private var secondary: Set<Muscle> = []
    @State private var equipment: Equipment = .barbell
    @State private var tracking: TrackingType = .weightReps
    @State private var isCompound = false
    @State private var instructions = ""
    @State private var tapMode: TapMode = .primary

    enum TapMode: String, CaseIterable, Identifiable {
        case primary = "Primary", secondary = "Secondary"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $name)
                        .font(.headline)
                }

                Section {
                    VStack(spacing: 12) {
                        Picker("Selecting", selection: $tapMode) {
                            ForEach(TapMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        BodyMapView(intensities: intensities, spacing: 20, showsLabels: true) { muscle in
                            toggle(muscle)
                        }
                        .frame(height: 300)
                        Text("Tap muscles to mark them as \(tapMode.rawValue.lowercased()).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    FlowLayout(spacing: 6) {
                        ForEach(Muscle.displayOrder) { m in
                            Button {
                                toggle(m)
                            } label: {
                                Chip(text: m.displayName, tint: primary.contains(m) || secondary.contains(m) ? Theme.ember : .secondary,
                                     filled: primary.contains(m))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Muscles Worked")
                }

                Section("Details") {
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { Label($0.displayName, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Track By", selection: $tracking) {
                        ForEach(TrackingType.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Compound Movement", isOn: $isCompound)
                }

                Section {
                    TextField("One step per line", text: $instructions, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("Optional. Cues like seat height or grip width are handy here.")
                }
            }
            .navigationTitle(existing == nil ? "New Exercise" : "Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || primary.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var intensities: [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for m in secondary { result[m] = 0.45 }
        for m in primary { result[m] = 1 }
        return result
    }

    private func toggle(_ muscle: Muscle) {
        withAnimation(.snappy) {
            switch tapMode {
            case .primary:
                secondary.remove(muscle)
                if primary.contains(muscle) { primary.remove(muscle) } else { primary.insert(muscle) }
            case .secondary:
                primary.remove(muscle)
                if secondary.contains(muscle) { secondary.remove(muscle) } else { secondary.insert(muscle) }
            }
        }
    }

    private func load() {
        guard let existing else { return }
        name = existing.name
        primary = Set(existing.primaryMusclesRaw.compactMap(Muscle.init(rawValue:)))
        secondary = Set(existing.secondaryMusclesRaw.compactMap(Muscle.init(rawValue:)))
        equipment = Equipment(rawValue: existing.equipmentRaw) ?? .other
        tracking = TrackingType(rawValue: existing.trackingRaw) ?? .weightReps
        isCompound = existing.isCompound
        instructions = existing.instructions
    }

    private func save() {
        let target = existing ?? CustomExercise(name: "")
        if existing == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.primaryMusclesRaw = Muscle.displayOrder.filter { primary.contains($0) }.map(\.rawValue)
        target.secondaryMusclesRaw = Muscle.displayOrder.filter { secondary.contains($0) }.map(\.rawValue)
        target.equipmentRaw = equipment.rawValue
        target.trackingRaw = tracking.rawValue
        target.isCompound = isCompound
        target.instructions = instructions
        try? context.save()
        library.update(custom: allCustom.contains(where: { $0.id == target.id }) ? allCustom : allCustom + [target])
        if existing == nil { onCreate?(target.info) }
        dismiss()
    }
}
