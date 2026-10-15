import SwiftUI

/// Floating rest countdown shown at the bottom of the workout screen.
struct RestTimerBar: View {
    @Environment(WorkoutManager.self) private var manager

    var body: some View {
        if let end = manager.restEndsAt {
            TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                let remaining = max(0, end.timeIntervalSince(timeline.date))
                let progress = manager.restTotal > 0 ? remaining / manager.restTotal : 0
                HStack(spacing: 14) {
                    ZStack {
                        ProgressRing(progress: progress, lineWidth: 5)
                        Image(systemName: "timer")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.ember)
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(Fmt.clock(remaining.rounded(.up)))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                        Text(manager.restCaption)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 4)
                    timerButton("−15") { manager.adjustRest(by: -15) }
                    timerButton("+15") { manager.adjustRest(by: 15) }
                    Button {
                        manager.skipRest()
                    } label: {
                        Text("Skip")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Theme.accentGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular.tint(Theme.ember.opacity(0.12)).interactive(), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
    }

    private func timerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 46, height: 36)
                .background(Color.subtleFill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Mini player shown above the tab bar while a workout is running.
struct ActiveWorkoutAccessory: View {
    @Environment(WorkoutManager.self) private var manager

    var body: some View {
        if let session = manager.activeSession {
            Button {
                manager.isPresented = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "dumbbell.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.accentGradient, in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(session.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let end = manager.restEndsAt, end > .now {
                            HStack(spacing: 3) {
                                Text("Rest")
                                Text(timerInterval: Date.now...end, countsDown: true)
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(Theme.ember)
                        } else {
                            Text(session.startedAt, style: .timer)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resume \(session.name)")
        }
    }
}
