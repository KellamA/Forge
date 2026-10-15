import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ExerciseLibrary.self) private var library

    @AppStorage(SettingsKey.userName) private var userName = ""
    @AppStorage(SettingsKey.weeklyGoal) private var weeklyGoal = SettingsDefaults.weeklyGoal
    @AppStorage(SettingsKey.weightIncrement) private var increment = SettingsDefaults.weightIncrement
    @AppStorage(SettingsKey.autoStartRest) private var autoStartRest = true
    @AppStorage(SettingsKey.oneRepMaxFormula) private var formulaRaw = OneRepMaxFormula.brzycki.rawValue
    @AppStorage(SettingsKey.barWeight) private var barWeight = SettingsDefaults.barWeight
    @AppStorage(SettingsKey.availablePlates) private var platesRaw = SettingsDefaults.platesString
    @AppStorage(SettingsKey.bodyModel) private var bodyModelRaw = BodyModel.male.rawValue
    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearanceSetting.system.rawValue
    @AppStorage(SettingsKey.healthConnected) private var healthConnected = false
    @AppStorage(SettingsKey.healthImportWeight) private var healthImportWeight = true
    @AppStorage(SettingsKey.healthSaveWeight) private var healthSaveWeight = true
    @AppStorage(SettingsKey.healthSaveWorkouts) private var healthSaveWorkouts = true

    @State private var exportURLs: [URL] = []
    @State private var showingExport = false
    @State private var confirmErase = false
    @State private var confirmDemo = false
    @State private var message: String?

    private static let allPlates: [Double] = [55, 45, 35, 25, 15, 10, 5, 2.5, 1.25]

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Your name", text: $userName)
                    Picker("Body Model", selection: $bodyModelRaw) {
                        ForEach(BodyModel.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                }

                Section {
                    ValueStepper(title: "Weekly Goal", value: $weeklyGoal, range: 1...14) { "\($0) sessions" }
                    Picker("Weight Increment", selection: $increment) {
                        Text("2.5 lb").tag(2.5)
                        Text("5 lb").tag(5.0)
                        Text("10 lb").tag(10.0)
                    }
                    Toggle("Auto-Start Rest Timer", isOn: $autoStartRest)
                        .tint(Theme.ember)
                } header: {
                    Text("Training")
                } footer: {
                    Text("The increment is used by the +/− keys while logging and for progression suggestions.")
                }

                Section {
                    Picker("Formula", selection: $formulaRaw) {
                        ForEach(OneRepMaxFormula.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                    let formula = OneRepMaxFormula(rawValue: formulaRaw) ?? .brzycki
                    VStack(alignment: .leading, spacing: 6) {
                        Text(formula.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Example: 185 lb × 6 → **\(Fmt.weight((OneRepMax.estimate(weight: 185, reps: 6, formula: formula) ?? 0).rounded())) lb** max")
                            .font(.footnote)
                    }
                } header: {
                    Text("Estimated One-Rep Max")
                } footer: {
                    Text("Sets over \(OneRepMax.maxReliableReps) reps are left out of 1RM estimates.")
                }

                Section("Plate Calculator") {
                    Picker("Bar Weight", selection: $barWeight) {
                        ForEach([45.0, 35.0, 25.0, 15.0], id: \.self) { Text("\(Fmt.weight($0)) lb").tag($0) }
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(Self.allPlates, id: \.self) { plate in
                            let on = plates.contains(plate)
                            Button {
                                togglePlate(plate)
                            } label: {
                                Text(Fmt.weight(plate))
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .foregroundStyle(on ? (plate < 10 ? Color.black : Color.white) : Color.primary)
                                    .background(on ? AnyShapeStyle(BarbellGraphic.color(for: plate)) : AnyShapeStyle(Color.subtleFill), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    if healthConnected {
                        Label("Connected to Apple Health", systemImage: "heart.fill")
                            .foregroundStyle(.pink)
                        Toggle("Import Weigh-ins", isOn: $healthImportWeight)
                        Toggle("Save Weigh-ins", isOn: $healthSaveWeight)
                        Toggle("Save Workouts & Runs", isOn: $healthSaveWorkouts)
                        Button("Import Weigh-ins Now") {
                            Task {
                                let n = await HealthKitManager.shared.importBodyWeights(context: context)
                                message = n == 0 ? "No new weigh-ins found." : "Imported \(n) weigh-ins."
                            }
                        }
                    } else {
                        Button {
                            Task {
                                let ok = await HealthKitManager.shared.requestAuthorization()
                                if ok {
                                    let n = await HealthKitManager.shared.importBodyWeights(context: context)
                                    if n > 0 { message = "Imported \(n) weigh-ins from Apple Health." }
                                } else {
                                    message = HealthKitManager.shared.lastError ?? "Couldn't connect to Apple Health."
                                }
                            }
                        } label: {
                            Label("Connect Apple Health", systemImage: "heart.text.square.fill")
                        }
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Forge reads body weight and saves workouts, runs (with distance) and weigh-ins. Calories are estimated.")
                }

                Section {
                    HStack {
                        Label("iCloud Sync", systemImage: "icloud.fill")
                        Spacer()
                        Text(FileManager.default.ubiquityIdentityToken != nil ? "On" : "Not signed in")
                            .foregroundStyle(.secondary)
                    }
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppearanceSetting.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                } footer: {
                    Text("Your data syncs automatically through your private iCloud account.")
                }

                Section {
                    Button {
                        exportURLs = CSVExporter.export(context: context)
                        showingExport = !exportURLs.isEmpty
                    } label: {
                        Label("Export Data (CSV)", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        PRService.recomputeAll(context: context)
                        message = "Personal records recalculated."
                    } label: {
                        Label("Recalculate Personal Records", systemImage: "trophy")
                    }
                    Button {
                        confirmDemo = true
                    } label: {
                        Label("Load Sample Data", systemImage: "wand.and.stars")
                    }
                    Button(role: .destructive) {
                        confirmErase = true
                    } label: {
                        Label("Erase All Data", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Sample data adds 12 weeks of example workouts, runs and weigh-ins so you can explore the app.")
                }

                Section {
                    NavigationLink("Acknowledgements") { AcknowledgementsView() }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showingExport) {
                ActivityView(items: exportURLs)
                    .presentationDetents([.medium, .large])
            }
            .confirmationDialog("Erase everything?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase All Data", role: .destructive) {
                    DemoData.eraseAll(context: context)
                    message = "All data erased."
                }
            } message: {
                Text("Splits, workouts, weigh-ins and photos will be deleted on all your devices. This can't be undone.")
            }
            .confirmationDialog("Load sample data?", isPresented: $confirmDemo, titleVisibility: .visible) {
                Button("Load Sample Data") {
                    DemoData.generate(context: context, library: library)
                    message = "Sample data loaded."
                }
            } message: {
                Text("This adds example history alongside your own data. You can erase it later with Erase All Data.")
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var plates: [Double] {
        platesRaw.split(separator: ",").compactMap { Double($0) }
    }

    private func togglePlate(_ plate: Double) {
        var set = Set(plates)
        if set.contains(plate) { set.remove(plate) } else { set.insert(plate) }
        platesRaw = set.sorted(by: >).map { Fmt.weight($0) }.joined(separator: ",")
    }
}

struct AcknowledgementsView: View {
    var body: some View {
        List {
            Section {
                Text("Exercise catalog based on free-exercise-db by yuhonas, released into the public domain under the Unlicense.")
            } header: {
                Text("free-exercise-db")
            }
            Section {
                Text("""
                Body map artwork from react-native-body-highlighter.

                MIT License

                Copyright (c) 2022 ELABBASSI Hicham

                Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

                The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

                THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
                """)
                .font(.footnote)
            } header: {
                Text("react-native-body-highlighter")
            }
        }
        .navigationTitle("Acknowledgements")
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Writes workouts, runs and weigh-ins to CSV files in a temporary folder.
@MainActor
enum CSVExporter {
    static func export(context: ModelContext) -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ForgeExport", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter()
        var urls: [URL] = []

        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
        var lifts = "date,workout,exercise,set,weight_lb,reps,seconds,warmup,pr\n"
        for s in sessions where s.endedAt != nil {
            for ex in s.orderedExercises {
                for (i, set) in ex.completedSets.enumerated() {
                    lifts += [iso.string(from: s.startedAt), quote(s.name), quote(ex.exerciseName), "\(i + 1)",
                              Fmt.weight(set.weight), "\(set.reps)", "\(set.seconds)", set.isWarmup ? "1" : "0",
                              set.prKind?.rawValue ?? ""].joined(separator: ",") + "\n"
                }
            }
        }
        urls.append(write(lifts, name: "forge-workouts.csv", in: dir))

        let runs = (try? context.fetch(FetchDescriptor<CardioLog>(sortBy: [SortDescriptor(\.date)]))) ?? []
        var cardio = "date,type,miles,duration_seconds,pace_per_mile\n"
        for r in runs {
            cardio += [iso.string(from: r.date), r.type.rawValue, Fmt.miles(r.distance), "\(Int(r.durationSeconds))",
                       r.pace.map { Fmt.pace($0).replacingOccurrences(of: " /mi", with: "") } ?? ""].joined(separator: ",") + "\n"
        }
        urls.append(write(cardio, name: "forge-cardio.csv", in: dir))

        let weights = (try? context.fetch(FetchDescriptor<BodyWeightEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        var body = "date,weight_lb,body_fat_pct,note\n"
        for w in weights {
            body += [iso.string(from: w.date), Fmt.weight(w.weight), w.bodyFat > 0 ? Fmt.weight(w.bodyFat) : "", quote(w.note)].joined(separator: ",") + "\n"
        }
        urls.append(write(body, name: "forge-bodyweight.csv", in: dir))
        return urls
    }

    private static func quote(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func write(_ text: String, name: String, in dir: URL) -> URL {
        let url = dir.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
