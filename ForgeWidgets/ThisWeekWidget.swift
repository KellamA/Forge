import SwiftUI
import WidgetKit

struct ThisWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.thisWeekKind, provider: SnapshotProvider()) { entry in
            ThisWeekView(entry: entry)
                .widgetURL(WidgetShared.todayURL)
        }
        .configurationDisplayName("This Week")
        .description("Sessions toward your weekly goal and your streak.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct ThisWeekView: View {
    let entry: ForgeEntry

    @Environment(\.widgetFamily) private var family

    private var done: Int { entry.state?.sessionsThisWeek ?? 0 }
    private var goal: Int { max(1, entry.weeklyGoal) }
    private var streak: Int { entry.state?.streak ?? 0 }
    private var progress: Double { min(1, Double(done) / Double(goal)) }

    var body: some View {
        if family == .accessoryCircular {
            circular
                .containerBackground(for: .widget) { Color.clear }
        } else {
            small
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
    }

    // MARK: - Lock Screen

    private var circular: some View {
        Gauge(value: Double(min(done, goal)), in: 0...Double(goal)) {
            Text("Week")
        } currentValueLabel: {
            VStack(spacing: 0) {
                Text("\(done)/\(goal)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                HStack(spacing: 1) {
                    Image(systemName: "flame.fill")
                    Text("\(streak)")
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel("\(done) of \(goal) sessions this week, \(streak) week streak")
    }

    // MARK: - Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("THIS WEEK")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if done >= goal {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WidgetTheme.ember)
                        .widgetAccentable()
                }
            }
            Spacer(minLength: 4)
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: max(0.001, progress))
                    .stroke(WidgetTheme.ringGradient, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(done > 0 ? 1 : 0)
                    .widgetAccentable()
                VStack(spacing: -2) {
                    Text("\(done)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("of \(goal)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 86, height: 86)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(WidgetTheme.accentGradient)
                    .widgetAccentable()
                Text(streakText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.caption.weight(.bold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(goal) sessions this week. \(streakText).")
    }

    private var streakText: String {
        if streak > 0 { return "\(streak) wk streak" }
        let left = goal - done
        return left > 0 ? "\(left) to go" : "Goal hit"
    }
}

#Preview(as: .systemSmall) {
    ThisWeekWidget()
} timeline: {
    ForgeEntry.sample
}

#Preview(as: .accessoryCircular) {
    ThisWeekWidget()
} timeline: {
    ForgeEntry.sample
}
