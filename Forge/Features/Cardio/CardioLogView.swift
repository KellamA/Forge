import SwiftData
import SwiftUI

struct CardioPrefill: Identifiable {
    let id = UUID()
    var type: CardioType = .outdoor
    var distance: Double = 2
    var splitID: UUID? = nil
    var dayID: UUID? = nil
    /// Attach the run to the in-progress workout instead of logging it on its own.
    var linkToActiveSession = false
}

struct CardioLogView: View {
    let prefill: CardioPrefill

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkoutManager.self) private var workout
    @AppStorage(SettingsKey.healthSaveWorkouts) private var saveToHealth = true

    @State private var type: CardioType = .outdoor
    @State private var distance: Double = 2
    @State private var hours = 0
    @State private var minutes = 18
    @State private var seconds = 0
    @State private var tracksTime = true
    @State private var date = Date()
    @State private var notes = ""
    @State private var usesLaps = false
    @State private var laps = 8

    private var duration: TimeInterval { TimeInterval(hours * 3600 + minutes * 60 + seconds) }
    private var effectiveDistance: Double { usesLaps && type == .track ? Double(laps) * CardioType.milesPerLap : distance }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        ForEach(CardioType.allCases) { option in
                            Button {
                                withAnimation(.snappy) { type = option }
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: option.symbol)
                                        .font(.title2)
                                    Text(option.displayName)
                                        .font(.caption.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity, minHeight: 74)
                                .foregroundStyle(type == option ? .white : .primary)
                                .background {
                                    if type == option {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardioGradient)
                                    } else {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.subtleFill)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .sensoryFeedback(.selection, trigger: type == option)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }

                Section("Distance") {
                    if type == .track {
                        Toggle("Count laps instead", isOn: $usesLaps.animation(.snappy))
                            .tint(Theme.cardio)
                    }
                    if usesLaps && type == .track {
                        ValueStepper(title: "Laps (400 m)", value: $laps, range: 1...200)
                        Text("= \(Fmt.miles(effectiveDistance)) mi")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            NumericField(placeholder: "0.0", value: $distance, font: .system(size: 34, weight: .bold, design: .rounded), alignment: .leading)
                            Text("miles")
                                .foregroundStyle(.secondary)
                            Spacer()
                            HStack(spacing: 0) {
                                quickButton("minus") { distance = max(0, ((distance - 0.25) * 4).rounded() / 4) }
                                quickButton("plus") { distance = ((distance + 0.25) * 4).rounded() / 4 }
                            }
                            .background(Color.subtleFill, in: Capsule())
                        }
                    }
                }

                Section {
                    Toggle("Log time", isOn: $tracksTime.animation(.snappy))
                        .tint(Theme.cardio)
                    if tracksTime {
                        HStack(spacing: 0) {
                            wheel(value: $hours, range: 0..<6, label: "hr")
                            wheel(value: $minutes, range: 0..<60, label: "min")
                            wheel(value: $seconds, range: 0..<60, label: "sec")
                        }
                        .frame(height: 130)
                        if duration > 0 && effectiveDistance > 0 {
                            HStack {
                                Text("Pace")
                                Spacer()
                                Text(Fmt.pace(duration / effectiveDistance))
                                    .font(.body.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Theme.cardio)
                            }
                        }
                    }
                } header: {
                    Text("Time")
                }

                Section {
                    DatePicker("When", selection: $date, in: ...Date.now)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(prefill.linkToActiveSession ? "Add Cardio" : "Log Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(effectiveDistance <= 0)
                }
            }
            .onAppear {
                type = prefill.type
                distance = prefill.distance
                laps = max(1, Int((prefill.distance / CardioType.milesPerLap).rounded()))
                minutes = min(59, Int((prefill.distance * 9).rounded()))
            }
        }
    }

    private func wheel(value: Binding<Int>, range: Range<Int>, label: String) -> some View {
        HStack(spacing: 2) {
            Picker(label, selection: value) {
                ForEach(range, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func quickButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .frame(width: 46, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let log = CardioLog(type: type, distance: (effectiveDistance * 100).rounded() / 100,
                            duration: tracksTime ? duration : 0, date: date)
        log.notes = notes
        context.insert(log)
        if prefill.linkToActiveSession, let session = workout.activeSession {
            log.session = session
            log.splitID = session.splitID
            log.splitDayID = session.splitDayID
        } else {
            log.splitID = prefill.splitID
            log.splitDayID = prefill.dayID
            SplitService.recordCompletion(splitID: prefill.splitID, dayID: prefill.dayID, at: date, context: context)
        }
        try? context.save()
        if saveToHealth {
            Task { await HealthKitManager.shared.save(cardio: log) }
        }
        dismiss()
    }
}
