import SwiftUI

// MARK: - Card

struct Card<Content: View>: View {
    var padding: CGFloat = Theme.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

extension View {
    func cardStyle(padding: CGFloat = Theme.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

// MARK: - Section header

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let title: String
    let value: String
    var unit: String? = nil
    var icon: String
    var tint: Color = Theme.ember
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .labelStyle(.titleAndIcon)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Chips

struct Chip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = .secondary
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(filled ? .white : tint)
        .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)), in: Capsule())
    }
}

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).imageScale(.small) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                if isSelected {
                    Capsule().fill(Theme.accentGradient)
                } else {
                    Capsule().fill(Color.subtleFill)
                }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.accentGradient

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Theme.ember.opacity(configuration.isPressed ? 0.15 : 0.32), radius: configuration.isPressed ? 6 : 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Icon badge

struct IconBadge: View {
    let systemName: String
    var gradient: LinearGradient = Theme.accentGradient
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 8
    var gradient: AngularGradient = AngularGradient(colors: [Theme.gold, Theme.ember, Theme.flame, Theme.gold], center: .center)

    var body: some View {
        ZStack {
            Circle().stroke(Color.subtleFill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0 ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
        }
    }
}

// MARK: - Numeric text field

/// A text field bound to a number that commits on every keystroke (so tapping "done" mid-edit never loses input).
struct NumericField: View {
    let placeholder: String
    @Binding var value: Double
    var allowsDecimal = true
    var font: Font = .body.weight(.semibold)
    var alignment: TextAlignment = .center

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(alignment)
            .font(font)
            .monospacedDigit()
            .focused($focused)
            .onAppear { text = format(value) }
            .onChange(of: value) { _, newValue in
                if !focused || Double(text) != newValue { text = format(newValue) }
            }
            .onChange(of: text) { _, newText in
                let cleaned = newText.replacingOccurrences(of: ",", with: ".")
                if cleaned.isEmpty { value = 0; return }
                if let parsed = Double(cleaned) { value = allowsDecimal ? parsed : parsed.rounded() }
            }
            .onChange(of: focused) { _, isFocused in
                if isFocused, value == 0 { text = "" }
                if !isFocused { text = format(value) }
            }
    }

    private func format(_ v: Double) -> String {
        guard v != 0 else { return "" }
        return allowsDecimal ? Fmt.weight(v) : String(Int(v))
    }
}

// MARK: - Stepper row

struct ValueStepper: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 0) {
                stepButton("minus", enabled: value - step >= range.lowerBound) { value -= step }
                Text(format(value))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 54)
                    .contentTransition(.numericText(value: Double(value)))
                stepButton("plus", enabled: value + step <= range.upperBound) { value += step }
            }
            .background(Color.subtleFill, in: Capsule())
        }
        .animation(.snappy, value: value)
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .frame(width: 46, height: 38)
                // Plain buttons only hit-test drawn pixels; make the whole pad tappable.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .sensoryFeedback(.selection, trigger: value)
    }
}

// MARK: - Empty state

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            IconBadge(systemName: icon, size: 52)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

// MARK: - Misc

struct GradientText: View {
    let text: String
    var font: Font = .largeTitle.weight(.heavy)
    var gradient: LinearGradient = Theme.accentGradient

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(gradient)
    }
}

extension View {
    /// Standard screen background.
    func screenBackground() -> some View {
        background(Color.appBackground.ignoresSafeArea())
    }
}
