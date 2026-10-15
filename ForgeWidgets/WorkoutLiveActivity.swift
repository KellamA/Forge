import ActivityKit
import SwiftUI
import WidgetKit

private let ember = Color(red: 1.0, green: 0.42, blue: 0.10)
private let gold = Color(red: 1.0, green: 0.74, blue: 0.24)
private let flame = Color(red: 0.96, green: 0.24, blue: 0.19)
private let accent = LinearGradient(colors: [gold, ember, flame], startPoint: .topLeading, endPoint: .bottomTrailing)

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(ember)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        BrandMark(size: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(context.attributes.workoutName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(context.attributes.startedAt, style: .timer)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let end = context.state.restEndsAt, end > .now {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("REST")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(ember)
                            Text(timerInterval: Date.now...end, countsDown: true)
                                .font(.title3.weight(.bold).monospacedDigit())
                                .multilineTextAlignment(.trailing)
                                .frame(width: 64)
                        }
                        .padding(.trailing, 4)
                    } else {
                        SetProgressRing(completed: context.state.completedSets, total: context.state.totalSets)
                            .frame(width: 34, height: 34)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(context.state.exerciseName)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()
                            Text(context.state.setLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if !context.state.detail.isEmpty {
                            Text(context.state.detail)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(ember)
                        }
                        if let end = context.state.restEndsAt, end > .now {
                            ProgressView(timerInterval: end.addingTimeInterval(-max(1, context.state.restTotal))...end, countsDown: true) {
                                EmptyView()
                            } currentValueLabel: {
                                EmptyView()
                            }
                            .tint(ember)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(ember)
            } compactTrailing: {
                if let end = context.state.restEndsAt, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(ember)
                        .frame(width: 44)
                } else {
                    Text("\(context.state.completedSets)/\(context.state.totalSets)")
                        .monospacedDigit()
                        .foregroundStyle(ember)
                }
            } minimal: {
                if let end = context.state.restEndsAt, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .monospacedDigit()
                        .font(.caption2)
                        .foregroundStyle(ember)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(ember)
                }
            }
            .keylineTint(ember)
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.attributes.workoutName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                        Text(context.attributes.startedAt, style: .timer)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                if let end = context.state.restEndsAt, end > .now {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("REST")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(ember)
                        Text(timerInterval: Date.now...end, countsDown: true)
                            .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110, alignment: .trailing)
                    }
                } else {
                    SetProgressRing(completed: context.state.completedSets, total: context.state.totalSets)
                        .frame(width: 44, height: 44)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(context.state.exerciseName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(context.state.setLabel)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                if !context.state.detail.isEmpty {
                    Text(context.state.detail)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(accent)
                }
                if let end = context.state.restEndsAt, end > .now {
                    ProgressView(timerInterval: end.addingTimeInterval(-max(1, context.state.restTotal))...end, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(ember)
                }
            }
        }
        .padding(16)
    }
}

private struct BrandMark: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "dumbbell.fill")
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(accent, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

private struct SetProgressRing: View {
    let completed: Int
    let total: Int

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 4)
            Circle()
                .trim(from: 0, to: total > 0 ? CGFloat(completed) / CGFloat(total) : 0)
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(completed)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}
