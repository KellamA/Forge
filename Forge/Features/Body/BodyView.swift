import SwiftData
import SwiftUI

struct BodyView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var entries: [BodyWeightEntry]
    @AppStorage(SettingsKey.goalWeight) private var goalWeight = 0.0
    @AppStorage(SettingsKey.healthConnected) private var healthConnected = false

    @State private var range: ChartRange = .quarter
    @State private var showingAdd = false
    @State private var editing: BodyWeightEntry?
    @State private var showingCompare = false
    @State private var showingGoal = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if entries.isEmpty {
                        EmptyStateCard(icon: "scalemass.fill", title: "Track your body weight",
                                       message: "Log a weigh-in (with an optional progress photo) and watch the trend line smooth out day-to-day noise.",
                                       actionTitle: "Log Weight") { showingAdd = true }
                    } else {
                        heroCard
                        chartCard
                        photosCard
                        entriesCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .navigationTitle("Body")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Set Goal Weight", systemImage: "target") { showingGoal = true }
                        if healthConnected {
                            Button("Import from Apple Health", systemImage: "heart.text.square") { importFromHealth() }
                        }
                        if entries.contains(where: { $0.photo != nil }) {
                            Button("Compare Photos", systemImage: "rectangle.split.2x1") { showingCompare = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Log Weight")
                }
            }
            .navigationDestination(for: AllEntriesLink.self) { _ in AllWeightEntriesView() }
            .sheet(isPresented: $showingAdd) { WeightEntryEditor(entry: nil) }
            .sheet(item: $editing) { WeightEntryEditor(entry: $0) }
            .sheet(isPresented: $showingCompare) { PhotoCompareView() }
            .sheet(isPresented: $showingGoal) { GoalWeightSheet(current: entries.first?.weight ?? 180) }
            .alert(importMessage ?? "", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        let latest = entries.first!
        let weekAgo = entries.first { $0.date <= Calendar.current.date(byAdding: .day, value: -7, to: latest.date)! }
        let monthAgo = entries.first { $0.date <= Calendar.current.date(byAdding: .day, value: -30, to: latest.date)! }
        let start = entries.last!
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white.opacity(0.85))
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Fmt.weight(latest.weight))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: latest.weight))
                        Text("lb")
                            .font(.title3.weight(.semibold))
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    Text(Fmt.relativeDay(latest.date) + " · " + latest.date.formatted(.dateTime.hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                if let photo = latest.photo, let image = UIImage(data: photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.5), lineWidth: 1))
                }
            }
            HStack(spacing: 8) {
                deltaChip("7 days", weekAgo.map { latest.weight - $0.weight })
                deltaChip("30 days", monthAgo.map { latest.weight - $0.weight })
                deltaChip("All time", entries.count > 1 ? latest.weight - start.weight : nil)
            }
            if goalWeight > 0 {
                goalProgress(latest: latest.weight, start: start.weight)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bodyGradient, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: Theme.body.opacity(0.35), radius: 16, y: 8)
        .onTapGesture { editing = latest }
    }

    private func deltaChip(_ label: String, _ delta: Double?) -> some View {
        VStack(spacing: 1) {
            Text(delta.map { Fmt.signed($0) } ?? "–")
                .font(.subheadline.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .opacity(0.8)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func goalProgress(latest: Double, start: Double) -> some View {
        let total = abs(start - goalWeight)
        let done = total > 0 ? max(0, min(1, 1 - abs(latest - goalWeight) / total)) : 1
        let remaining = latest - goalWeight
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Goal \(Fmt.weight(goalWeight)) lb", systemImage: "target")
                Spacer()
                Text(abs(remaining) < 0.25 ? "Goal reached 🎉" : "\(Fmt.weight(abs(remaining).rounded(toPlaces: 1))) lb to go")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white).frame(width: max(8, geo.size.width * done))
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        let start = range.startDate
        let ascending = entries.reversed().filter { start == nil || $0.date >= start! }
        let points = ascending.map { TrendPoint(id: $0.id, date: $0.date, value: $0.weight) }
        let smoothed = Self.movingAverage(Array(ascending))
        let values = ascending.map(\.weight)
        let rate = Self.weeklyRate(Array(entries.reversed()))
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trend")
                        .font(.headline)
                    Text("Dots are weigh-ins · line is your 7-day average")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if points.count >= 2 {
                TrendChart(points: points, smoothed: smoothed, goal: goalWeight > 0 ? goalWeight : nil,
                           tint: Theme.body, unit: "lb", height: 220)
            } else {
                Text("Log at least two weigh-ins in this range to see a trend.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
            RangePicker(range: $range)
            HStack(spacing: 10) {
                stat("Low", values.min().map { Fmt.weight($0) } ?? "–")
                stat("High", values.max().map { Fmt.weight($0) } ?? "–")
                stat("Average", values.isEmpty ? "–" : Fmt.weight((values.reduce(0, +) / Double(values.count)).rounded(toPlaces: 1)))
                stat("Per Week", rate.map { Fmt.signed($0, digits: 1) } ?? "–")
            }
        }
        .cardStyle()
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.body.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Time-based trailing 7-day average.
    static func movingAverage(_ ascending: [BodyWeightEntry]) -> [TrendPoint] {
        var result: [TrendPoint] = []
        var window: [BodyWeightEntry] = []
        for entry in ascending {
            window.append(entry)
            window.removeAll { entry.date.timeIntervalSince($0.date) > 7 * 86400 }
            let avg = window.reduce(0) { $0 + $1.weight } / Double(window.count)
            result.append(TrendPoint(id: UUID(), date: entry.date, value: avg))
        }
        return result
    }

    /// Least-squares slope over the last 28 days, in lb per week.
    static func weeklyRate(_ ascending: [BodyWeightEntry]) -> Double? {
        guard let last = ascending.last else { return nil }
        let cutoff = last.date.addingTimeInterval(-28 * 86400)
        let recent = ascending.filter { $0.date >= cutoff }
        guard recent.count >= 3 else { return nil }
        let xs = recent.map { $0.date.timeIntervalSince(cutoff) / 86400 }
        let ys = recent.map(\.weight)
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard den > 0 else { return nil }
        return num / den * 7
    }

    // MARK: - Photos

    @ViewBuilder
    private var photosCard: some View {
        let withPhotos = entries.filter { $0.photo != nil }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Progress Photos")
                    .font(.headline)
                Spacer()
                if withPhotos.count >= 2 {
                    Button("Compare") { showingCompare = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.body)
                }
            }
            if withPhotos.isEmpty {
                Button {
                    showingAdd = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.body)
                            .frame(width: 56, height: 72)
                            .background(Theme.body.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text("Add a photo with your next weigh-in to see your transformation side by side.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(withPhotos) { entry in
                            Button {
                                editing = entry
                            } label: {
                                PhotoThumb(entry: entry)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, Theme.cardPadding)
                }
                .padding(.horizontal, -Theme.cardPadding)
            }
        }
        .cardStyle()
    }

    // MARK: - Entries

    private var entriesCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Weigh-ins")
                    .font(.headline)
                Spacer()
                NavigationLink("See All", value: AllEntriesLink())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.body)
            }
            .padding(.bottom, 6)
            ForEach(Array(entries.prefix(7).enumerated()), id: \.element.id) { index, entry in
                let previous = index + 1 < entries.count ? entries[index + 1] : nil
                Button {
                    editing = entry
                } label: {
                    WeightEntryRow(entry: entry, previous: previous)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { editing = entry }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        context.delete(entry)
                        try? context.save()
                    }
                }
                if index < min(6, entries.count - 1) { Divider() }
            }
        }
        .cardStyle()
    }

    private func importFromHealth() {
        Task {
            let count = await HealthKitManager.shared.importBodyWeights(context: context)
            importMessage = count == 0 ? "You're up to date. No new weigh-ins in Apple Health." : "Imported \(count) weigh-in\(count == 1 ? "" : "s") from Apple Health."
        }
    }
}

struct AllEntriesLink: Hashable {}

struct WeightEntryRow: View {
    let entry: BodyWeightEntry
    let previous: BodyWeightEntry?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    if !entry.healthKitUUID.isEmpty {
                        Image(systemName: "heart.fill").foregroundStyle(.pink)
                    }
                    if entry.photo != nil {
                        Image(systemName: "camera.fill").foregroundStyle(Theme.body)
                    }
                    if entry.bodyFat > 0 {
                        Text("\(entry.bodyFat.formatted(.number.precision(.fractionLength(0...1))))% BF")
                    }
                    if !entry.note.isEmpty {
                        Text(entry.note).lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let previous {
                let delta = entry.weight - previous.weight
                Text(Fmt.signed(delta))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(abs(delta) < 0.05 ? Color.secondary : (delta < 0 ? Theme.success : Theme.ember))
            }
            Text("\(Fmt.weight(entry.weight)) lb")
                .font(.body.weight(.semibold).monospacedDigit())
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct PhotoThumb: View {
    let entry: BodyWeightEntry

    var body: some View {
        VStack(spacing: 4) {
            if let data = entry.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption2.weight(.semibold))
            Text("\(Fmt.weight(entry.weight)) lb")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

struct AllWeightEntriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var entries: [BodyWeightEntry]
    @State private var editing: BodyWeightEntry?

    var body: some View {
        List {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                Button {
                    editing = entry
                } label: {
                    WeightEntryRow(entry: entry, previous: index + 1 < entries.count ? entries[index + 1] : nil)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                offsets.map { entries[$0] }.forEach { context.delete($0) }
                try? context.save()
            }
        }
        .navigationTitle("All Weigh-ins")
        .sheet(item: $editing) { WeightEntryEditor(entry: $0) }
    }
}

private struct GoalWeightSheet: View {
    let current: Double
    @AppStorage(SettingsKey.goalWeight) private var goalWeight = 0.0
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "target")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.bodyGradient)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    NumericField(placeholder: Fmt.weight(current), value: $value, font: .system(size: 56, weight: .bold, design: .rounded))
                        .frame(width: 180)
                    Text("lb").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                }
                if value > 0 {
                    Text(value < current ? "Lose \(Fmt.weight((current - value).rounded(toPlaces: 1))) lb" : "Gain \(Fmt.weight((value - current).rounded(toPlaces: 1))) lb")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if goalWeight > 0 {
                    Button("Remove Goal", role: .destructive) {
                        goalWeight = 0
                        dismiss()
                    }
                }
            }
            .padding(.top, 24)
            .padding(.horizontal)
            .navigationTitle("Goal Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        goalWeight = value
                        dismiss()
                    }
                    .disabled(value <= 0)
                }
            }
            .onAppear { value = goalWeight > 0 ? goalWeight : 0 }
        }
        .presentationDetents([.medium])
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
