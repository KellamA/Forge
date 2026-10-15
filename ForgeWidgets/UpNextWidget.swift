import SwiftUI
import UIKit
import WidgetKit

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.upNextKind, provider: SnapshotProvider()) { entry in
            UpNextView(entry: entry)
                .widgetURL(WidgetShared.todayURL)
        }
        .configurationDisplayName("Up Next")
        .description("The next workout in your split and the muscles it hits.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct UpNextView: View {
    let entry: ForgeEntry

    @Environment(\.widgetFamily) private var family

    private var state: WidgetSnapshot.Entry? { entry.state }
    private var day: WidgetSnapshot.Day? { state?.day }
    private var isMedium: Bool { family == .systemMedium }

    var body: some View {
        Group {
            if isMedium {
                HStack(alignment: .center, spacing: 14) {
                    details
                    Spacer(minLength: 0)
                    artwork(width: 112, height: 108)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 4) {
                        header
                        Spacer(minLength: 0)
                        artwork(width: 66, height: 64)
                    }
                    Spacer(minLength: 4)
                    title
                    subtitle
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { background }
    }

    // MARK: - Pieces

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 6)
            title
            subtitle
            if let day, !day.muscles.isEmpty {
                Text(day.muscles.prefix(4).joined(separator: " · "))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .padding(.top, 6)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            if let headerSymbol {
                Image(systemName: headerSymbol)
            }
            Text(headerText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .layoutPriority(1)
        .font(.caption2.weight(.heavy))
        .foregroundStyle(.white.opacity(0.85))
        .widgetAccentable()
    }

    private var title: some View {
        Text(titleText)
            .font(.system(size: isMedium ? 28 : 24, weight: .bold, design: .rounded))
            .lineLimit(2)
            .minimumScaleFactor(0.6)
    }

    private var subtitle: some View {
        Text(subtitleText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(isMedium ? 1 : 2)
            .padding(.top, 1)
    }

    @ViewBuilder
    private func artwork(width: CGFloat, height: CGFloat) -> some View {
        if let image = bodyMapImage {
            Image(uiImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .scaledToFit()
                .frame(width: width, height: height)
                .padding(isMedium ? 6 : 0)
                .background(.white.opacity(isMedium ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Image(systemName: symbol)
                .font(.system(size: isMedium ? 46 : 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: isMedium ? width : nil, height: isMedium ? height : nil)
                .widgetAccentable()
        }
    }

    private var background: some View {
        Group {
            if state?.status == .rest || day?.kind == "rest" {
                WidgetTheme.restGradient
            } else if day?.kind == "cardio" {
                WidgetTheme.cardioGradient
            } else {
                WidgetTheme.accentGradient
            }
        }
    }

    // MARK: - Text

    private var headerText: String {
        guard let state else { return "FORGE" }
        switch state.status {
        case .noSplit, .emptySplit: return "FORGE"
        case .today: return "TODAY"
        case .upNext: return "UP NEXT"
        case .rest: return day == nil ? "REST DAY" : (isMedium ? "REST DAY · NEXT UP" : "NEXT")
        case .doneToday: return isMedium ? "DONE TODAY · NEXT UP" : "NEXT"
        }
    }

    /// Small widgets drop "rest day" / "done today" from the header text, so the icon carries it.
    private var headerSymbol: String? {
        switch state?.status {
        case .doneToday: "checkmark.circle.fill"
        case .rest where day != nil: "moon.zzz.fill"
        default: nil
        }
    }

    private var titleText: String {
        guard let state else { return "Open Forge" }
        switch state.status {
        case .noSplit: return "No plan yet"
        case .emptySplit: return "Add workouts"
        default: return day?.name ?? "Recover"
        }
    }

    private var subtitleText: String {
        guard let state else { return "to load your plan" }
        switch state.status {
        case .noSplit: return "Pick a split to see what's next."
        case .emptySplit: return "Your split has no days yet."
        default: break
        }
        guard let day else { return "Rest up and come back stronger." }
        var parts: [String] = []
        if let when = whenText(state.dayDate) { parts.append(when) }
        switch day.kind {
        case "cardio":
            let miles = (day.cardioMiles ?? 0).formatted(.number.precision(.fractionLength(0...2)))
            parts.append("\(miles) mi\(day.cardioType.map { " · \($0)" } ?? "")")
        case "rest":
            parts.append("Recover & recharge")
        default:
            parts.append(day.exerciseCount == 0 ? "No exercises yet"
                         : "\(day.exerciseCount) \(day.exerciseCount == 1 ? "exercise" : "exercises")")
            if isMedium && day.exerciseCount > 0 { parts.append("~\(day.estimatedMinutes) min") }
        }
        return parts.joined(separator: " · ")
    }

    private func whenText(_ date: Date?) -> String? {
        guard let date else { return nil }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: entry.date) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: entry.date), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return date.formatted(.dateTime.weekday(.wide))
    }

    private var symbol: String {
        guard let state else { return "flame.fill" }
        switch state.status {
        case .noSplit: return "flame.fill"
        case .emptySplit: return "calendar.badge.plus"
        default: return day?.symbol ?? "moon.zzz.fill"
        }
    }

    private var bodyMapImage: UIImage? {
        guard let file = day?.bodyMapFile, let url = WidgetShared.containerURL?.appending(path: file) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

#Preview(as: .systemSmall) {
    UpNextWidget()
} timeline: {
    ForgeEntry.sample
}

#Preview(as: .systemMedium) {
    UpNextWidget()
} timeline: {
    ForgeEntry.sample
}
