import SwiftUI

/// Front/back anatomical figure with muscles shaded by intensity (0…1).
struct BodyMapView: View {
    var intensities: [Muscle: Double]
    var sides: [BodySide] = [.front, .back]
    var tint: Color = Theme.ember
    var spacing: CGFloat = 10
    /// Draw for a colored background (darker base, solid highlights).
    var onColor = false
    var showsLabels = false
    var onTapMuscle: ((Muscle) -> Void)? = nil

    @AppStorage(SettingsKey.bodyModel) private var modelRaw = BodyModel.male.rawValue

    private var model: BodyModel { BodyModel(rawValue: modelRaw) ?? .male }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(sides) { side in
                VStack(spacing: 6) {
                    if let figure = BodyMapStore.shared.figure(model, side) {
                        BodyFigureView(figure: figure, intensities: intensities, tint: tint, onTapMuscle: onTapMuscle, onColor: onColor)
                            .aspectRatio(figure.size.width / figure.size.height, contentMode: .fit)
                    }
                    if showsLabels {
                        Text(side == .front ? "Front" : "Back")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let worked = intensities.filter { $0.value > 0 }.keys.map(\.displayName).sorted()
        return worked.isEmpty ? "Body map" : "Body map highlighting \(worked.joined(separator: ", "))"
    }
}

struct BodyFigureView: View {
    let figure: BodyFigure
    let intensities: [Muscle: Double]
    let tint: Color
    var onTapMuscle: ((Muscle) -> Void)?
    /// Region of the figure (in figure coordinates) to fit into the view. Defaults to the whole figure.
    var focus: CGRect? = nil
    var onColor = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let transform = transform(for: size)
            let dark = colorScheme == .dark
            let silhouette = onColor ? Color.black.opacity(0.06) : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.035))
            let baseMuscle = onColor ? Color.black.opacity(0.22) : (dark ? Color.white.opacity(0.13) : Color.black.opacity(0.10))
            let nonMuscle = onColor ? Color.black.opacity(0.14) : (dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            let outlineColor = onColor ? Color.white.opacity(0.35) : (dark ? Color.white.opacity(0.22) : Color.black.opacity(0.18))

            let outline = figure.outline.applying(transform)
            context.fill(outline, with: .color(silhouette))

            for region in figure.regions {
                let path = region.path.applying(transform)
                guard let muscle = region.muscle else {
                    context.fill(path, with: .color(nonMuscle))
                    continue
                }
                // Abductors (glute medius) have no separate shape, so they shade the glutes.
                let intensity = max(intensities[muscle] ?? 0, muscle == .glutes ? (intensities[.abductors] ?? 0) : 0)
                context.fill(path, with: .color(baseMuscle))
                if intensity > 0 {
                    context.fill(path, with: .color(tint.opacity((onColor ? 0.45 : 0.25) + (onColor ? 0.55 : 0.75) * min(1, intensity))))
                }
            }
            context.stroke(outline, with: .color(outlineColor), lineWidth: max(0.5, size.width / 260))
        }
        .overlay {
            if onTapMuscle != nil {
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { location in
                            let t = transform(for: geo.size).inverted()
                            let point = location.applying(t)
                            if let hit = figure.regions.last(where: { $0.muscle != nil && $0.path.contains(point) }),
                               let muscle = hit.muscle {
                                onTapMuscle?(muscle)
                            }
                        }
                }
            }
        }
    }

    private func transform(for size: CGSize) -> CGAffineTransform {
        let rect = focus ?? CGRect(origin: .zero, size: figure.size)
        let scale = min(size.width / rect.width, size.height / rect.height)
        let dx = size.width / 2 - rect.midX * scale
        let dy = size.height / 2 - rect.midY * scale
        return CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
    }
}

/// Compact single-side figure for list rows, zoomed in on the muscles the exercise works.
struct MuscleThumbnail: View {
    let primary: [Muscle]
    var secondary: [Muscle] = []
    var size: CGFloat = 44

    @AppStorage(SettingsKey.bodyModel) private var modelRaw = BodyModel.male.rawValue

    var body: some View {
        let side = Self.bestSide(primary: primary, secondary: secondary)
        let model = BodyModel(rawValue: modelRaw) ?? .male
        ZStack {
            if let figure = BodyMapStore.shared.figure(model, side) {
                BodyFigureView(figure: figure,
                               intensities: Self.intensities(primary: primary, secondary: secondary),
                               tint: Theme.ember,
                               focus: Self.focusRect(figure: figure, muscles: Set(primary)))
            }
        }
        .frame(width: size, height: size)
        .background(Color.subtleFill.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        .accessibilityHidden(true)
    }

    /// A square window around the highlighted muscles, at least ~40% of the figure tall.
    static func focusRect(figure: BodyFigure, muscles: Set<Muscle>) -> CGRect {
        let full = CGRect(origin: .zero, size: figure.size)
        let boxes = figure.regions.compactMap { region -> CGRect? in
            guard let m = region.muscle, muscles.contains(m) || (m == .glutes && muscles.contains(.abductors)) else { return nil }
            return region.path.boundingRect
        }
        guard var rect = boxes.first else { return full }
        for box in boxes.dropFirst() { rect = rect.union(box) }
        let side = min(max(rect.width, rect.height, figure.size.height * 0.4) * 1.18, figure.size.width)
        var origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        origin.x = min(max(0, origin.x), figure.size.width - side)
        origin.y = min(max(0, origin.y), figure.size.height - side)
        return CGRect(origin: origin, size: CGSize(width: side, height: side))
    }

    static func bestSide(primary: [Muscle], secondary: [Muscle]) -> BodySide {
        let front = primary.filter { $0.preferredSide == .front }.count
        let back = primary.filter { $0.preferredSide == .back }.count
        if front == back {
            let sf = secondary.filter { $0.preferredSide == .front }.count
            let sb = secondary.filter { $0.preferredSide == .back }.count
            return sb > sf ? .back : .front
        }
        return back > front ? .back : .front
    }

    static func intensities(primary: [Muscle], secondary: [Muscle]) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for m in secondary { result[m] = 0.45 }
        for m in primary { result[m] = 1 }
        return result
    }
}

/// Legend dots for primary/secondary shading.
struct BodyMapLegend: View {
    var tint: Color = Theme.ember

    var body: some View {
        HStack(spacing: 14) {
            legendItem(opacity: 1, label: "Primary")
            legendItem(opacity: 0.55, label: "Secondary")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private func legendItem(opacity: Double, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint.opacity(opacity)).frame(width: 9, height: 9)
            Text(label)
        }
    }
}
