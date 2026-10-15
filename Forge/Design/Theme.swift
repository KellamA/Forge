import SwiftUI

enum Theme {
    static let ember = Color(red: 1.0, green: 0.42, blue: 0.10)
    static let flame = Color(red: 0.96, green: 0.24, blue: 0.19)
    static let gold = Color(red: 1.0, green: 0.74, blue: 0.24)
    static let cardio = Color(red: 0.16, green: 0.72, blue: 0.98)
    static let body = Color(red: 0.58, green: 0.45, blue: 1.0)
    static let success = Color(red: 0.20, green: 0.80, blue: 0.45)
    static let rest = Color(red: 0.45, green: 0.52, blue: 0.95)

    static let accentGradient = LinearGradient(
        colors: [gold, ember, flame], startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let cardioGradient = LinearGradient(
        colors: [Color(red: 0.35, green: 0.85, blue: 1.0), cardio, Color(red: 0.20, green: 0.45, blue: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let restGradient = LinearGradient(
        colors: [Color(red: 0.55, green: 0.60, blue: 1.0), Color(red: 0.40, green: 0.32, blue: 0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let bodyGradient = LinearGradient(
        colors: [Color(red: 0.75, green: 0.55, blue: 1.0), body, Color(red: 0.40, green: 0.30, blue: 0.95)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let cornerRadius: CGFloat = 24
    static let cardPadding: CGFloat = 18
}

extension Color {
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let appBackground = Color(.systemGroupedBackground)
    static let subtleFill = Color(.tertiarySystemFill)
}

extension ShapeStyle where Self == Color {
    static var ember: Color { Theme.ember }
}
