import SwiftData
import SwiftUI
import UserNotifications

/// First-launch flow: welcome, profile, starting split, permissions.
struct WelcomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(ExerciseLibrary.self) private var library
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false
    @AppStorage(SettingsKey.userName) private var userName = ""
    @AppStorage(SettingsKey.bodyModel) private var bodyModelRaw = BodyModel.male.rawValue
    @AppStorage(SettingsKey.weeklyGoal) private var weeklyGoal = SettingsDefaults.weeklyGoal

    @State private var step = 0
    @State private var templateID: String? = SplitTemplate.pushPullLegs.id
    @State private var healthDone = false
    @State private var notificationsDone = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                progressDots
                    .padding(.top, 12)
                Group {
                    switch step {
                    case 0: intro
                    case 1: profile
                    case 2: splitChoice
                    default: permissions
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .frame(maxHeight: .infinity)
                footer
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.subtleFill))
                    .frame(width: i == step ? 26 : 8, height: 8)
            }
        }
    }

    // MARK: Steps

    private var intro: some View {
        ScrollView {
            VStack(spacing: 26) {
                ZStack {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Theme.accentGradient)
                        .frame(width: 116, height: 116)
                        .shadow(color: Theme.ember.opacity(0.5), radius: 24, y: 12)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-38))
                }
                .padding(.top, 40)
                VStack(spacing: 8) {
                    Text("Forge")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                    Text("Plan it. Lift it. Watch yourself get stronger.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 18) {
                    feature("calendar", "Smart splits", "Weekly schedules or rotations that pick up where you left off.")
                    feature("checklist", "Fast set logging", "Last session's numbers pre-filled, a rest timer and Live Activity.")
                    feature("chart.line.uptrend.xyaxis", "Real progress", "Estimated 1RM trends, PRs, volume and muscle balance.")
                    feature("figure", "Body tracking", "Weigh-ins, progress photos and Apple Health sync.")
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)
        }
    }

    private func feature(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(systemName: icon, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var profile: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header("About you", "A couple of quick things to personalize Forge.")
                VStack(alignment: .leading, spacing: 8) {
                    Text("What should we call you?")
                        .font(.subheadline.weight(.semibold))
                    TextField("First name (optional)", text: $userName)
                        .font(.title3.weight(.semibold))
                        .padding(14)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Body map figure")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 12) {
                        ForEach(BodyModel.allCases) { model in
                            let selected = bodyModelRaw == model.rawValue
                            Button {
                                bodyModelRaw = model.rawValue
                            } label: {
                                VStack(spacing: 8) {
                                    if let figure = BodyMapStore.shared.figure(model, .front) {
                                        BodyFigureView(figure: figure, intensities: [.chest: 1, .abs: 1, .quads: 0.45], tint: Theme.ember)
                                            .aspectRatio(figure.size.width / figure.size.height, contentMode: .fit)
                                            .frame(height: 150)
                                    }
                                    Text(model.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(selected ? Theme.ember : .clear, lineWidth: 2.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weekly goal")
                        .font(.subheadline.weight(.semibold))
                    ValueStepper(title: "Sessions per week", value: $weeklyGoal, range: 1...14)
                        .padding(14)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var splitChoice: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header("Pick a starting split", "You can edit everything later, or build your own from scratch.")
                ForEach(SplitTemplate.all) { template in
                    choiceRow(id: template.id, icon: template.icon, title: template.name,
                              subtitle: template.daysPerWeek, detail: template.summary)
                }
                choiceRow(id: nil, icon: "square.and.pencil", title: "I'll build my own",
                          subtitle: "Start blank", detail: "Head to the Plan tab to create your split.")
            }
            .padding(24)
        }
    }

    private func choiceRow(id: String?, icon: String, title: String, subtitle: String, detail: String) -> some View {
        let selected = templateID == id
        return Button {
            templateID = id
        } label: {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemName: icon, gradient: selected ? Theme.accentGradient : LinearGradient(colors: [Color.gray.opacity(0.55)], startPoint: .top, endPoint: .bottom), size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption.weight(.semibold)).foregroundStyle(Theme.ember)
                    Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.ember : .secondary)
            }
            .padding(16)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(selected ? Theme.ember : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }

    private var permissions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header("Connect", "Both are optional and can be changed in Settings.")
                permissionCard(icon: "heart.fill", tint: .pink, title: "Apple Health",
                               text: "Import weigh-ins from your scale and save workouts and runs to Health.",
                               done: healthDone) {
                    Task {
                        healthDone = await HealthKitManager.shared.requestAuthorization()
                        if healthDone { await HealthKitManager.shared.importBodyWeights(context: context) }
                    }
                }
                permissionCard(icon: "bell.badge.fill", tint: Theme.ember, title: "Rest Timer Alerts",
                               text: "Get a nudge when rest is over, even if your phone is in your pocket.",
                               done: notificationsDone) {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                        DispatchQueue.main.async { notificationsDone = granted }
                    }
                }
            }
            .padding(24)
        }
    }

    private func permissionCard(icon: String, tint: Color, title: String, text: String, done: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(done ? "On" : "Allow", action: action)
                .buttonStyle(.borderedProminent)
                .tint(done ? Theme.success : tint)
                .disabled(done)
        }
        .padding(16)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.weight(.bold))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    step -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 54, height: 54)
                        .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Button(step == 0 ? "Get Started" : (step == 3 ? "Start Training" : "Continue")) {
                if step < 3 {
                    step += 1
                } else {
                    finish()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func finish() {
        if let templateID, let template = SplitTemplate.all.first(where: { $0.id == templateID }) {
            let hasSplits = ((try? context.fetchCount(FetchDescriptor<WorkoutSplit>())) ?? 0) > 0
            if !hasSplits {
                template.instantiate(in: context, library: library, activate: true)
            }
        }
        hasOnboarded = true
    }
}
