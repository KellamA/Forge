import SwiftUI

/// Shows which plates to load on each side of the bar for a target weight.
struct PlateCalculatorView: View {
    let initialWeight: Double

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.barWeight) private var barWeight = SettingsDefaults.barWeight
    @AppStorage(SettingsKey.availablePlates) private var platesRaw = SettingsDefaults.platesString
    @State private var target: Double = 135

    private var plates: [Double] {
        platesRaw.split(separator: ",").compactMap { Double($0) }.sorted(by: >)
    }

    static func load(target: Double, bar: Double, plates: [Double]) -> (perSide: [Double], achieved: Double) {
        var remaining = max(0, (target - bar) / 2)
        var result: [Double] = []
        for plate in plates.sorted(by: >) where plate > 0 {
            while remaining + 0.001 >= plate {
                result.append(plate)
                remaining -= plate
            }
        }
        let achieved = bar + 2 * result.reduce(0, +)
        return (result, achieved)
    }

    var body: some View {
        let loadout = Self.load(target: target, bar: barWeight, plates: plates)
        NavigationStack {
            VStack(spacing: 22) {
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        stepButton("minus") { target = max(barWeight, target - 5) }
                        VStack(spacing: 0) {
                            Text(Fmt.weight(target))
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText(value: target))
                            Text("pounds")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 160)
                        stepButton("plus") { target += 5 }
                    }
                    if abs(loadout.achieved - target) > 0.01 {
                        Text("Closest you can load: \(Fmt.weight(loadout.achieved)) lb")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                BarbellGraphic(plates: loadout.perSide)
                    .frame(height: 150)
                    .padding(.horizontal)

                VStack(spacing: 8) {
                    Text("Per side")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    if loadout.perSide.isEmpty {
                        Text("Just the bar (\(Fmt.weight(barWeight)) lb)")
                            .font(.headline)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(groupedPlates(loadout.perSide), id: \.plate) { item in
                                HStack(spacing: 6) {
                                    Circle().fill(BarbellGraphic.color(for: item.plate)).frame(width: 12, height: 12)
                                    Text("\(item.count) × \(Fmt.weight(item.plate))")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.subtleFill, in: Capsule())
                            }
                        }
                    }
                    Text("Bar: \(Fmt.weight(barWeight)) lb · change plates in Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                Spacer()
            }
            .padding(.top, 12)
            .animation(.snappy, value: target)
            .navigationTitle("Plate Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { target = max(barWeight, initialWeight) }
        }
    }

    private func groupedPlates(_ plates: [Double]) -> [(plate: Double, count: Int)] {
        var counts: [Double: Int] = [:]
        plates.forEach { counts[$0, default: 0] += 1 }
        return counts.keys.sorted(by: >).map { ($0, counts[$0]!) }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .frame(width: 52, height: 52)
                .background(Color.subtleFill, in: Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: target)
    }
}

struct BarbellGraphic: View {
    let plates: [Double]

    static func color(for plate: Double) -> Color {
        switch plate {
        case 45...: Theme.flame
        case 35..<45: Theme.gold
        case 25..<35: Theme.success
        case 10..<25: Theme.cardio
        case 5..<10: Color(white: 0.85)
        default: Color(white: 0.6)
        }
    }

    private func height(for plate: Double) -> CGFloat {
        switch plate {
        case 45...: 1.0
        case 35..<45: 0.88
        case 25..<35: 0.74
        case 10..<25: 0.58
        case 5..<10: 0.44
        default: 0.34
        }
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            HStack(spacing: 0) {
                // Sleeve end
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 14, height: h * 0.16)
                HStack(spacing: 3) {
                    ForEach(Array(plates.reversed().enumerated()), id: \.offset) { _, plate in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Self.color(for: plate).gradient)
                            .frame(width: plate >= 25 ? 22 : 15, height: h * height(for: plate))
                            .overlay(
                                Text(Fmt.weight(plate))
                                    .font(.system(size: 8, weight: .heavy))
                                    .rotationEffect(.degrees(-90))
                                    .foregroundStyle(.black.opacity(0.55))
                                    .fixedSize()
                            )
                    }
                }
                // Collar and shaft
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray)
                    .frame(width: 10, height: h * 0.24)
                Rectangle()
                    .fill(LinearGradient(colors: [Color.gray.opacity(0.9), Color.gray.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                    .frame(height: h * 0.08)
            }
            .frame(maxHeight: .infinity)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: plates)
    }
}
