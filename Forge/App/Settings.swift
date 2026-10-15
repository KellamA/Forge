import Foundation

/// UserDefaults keys for @AppStorage settings.
enum SettingsKey {
    static let hasOnboarded = "hasOnboarded"
    static let userName = "userName"
    static let bodyModel = "bodyModel"
    static let appearance = "appearance"
    static let oneRepMaxFormula = "oneRepMaxFormula"
    static let weeklyGoal = "weeklyGoal"
    static let defaultRestSeconds = "defaultRestSeconds"
    static let weightIncrement = "weightIncrement"
    static let autoStartRest = "autoStartRest"
    static let barWeight = "barWeight"
    static let availablePlates = "availablePlates"
    static let goalWeight = "goalWeight"
    static let healthImportWeight = "healthImportWeight"
    static let healthSaveWeight = "healthSaveWeight"
    static let healthSaveWorkouts = "healthSaveWorkouts"
    static let healthConnected = "healthConnected"
    static let restTimerEnd = "restTimerEnd"
    static let restTimerTotal = "restTimerTotal"
}

enum SettingsDefaults {
    static let weeklyGoal = 4
    static let defaultRestSeconds = 120
    static let weightIncrement = 5.0
    static let barWeight = 45.0
    static let plates: [Double] = [45, 35, 25, 10, 5, 2.5]
    static let platesString = "45,35,25,10,5,2.5"

    static func register() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.weeklyGoal: weeklyGoal,
            SettingsKey.defaultRestSeconds: defaultRestSeconds,
            SettingsKey.weightIncrement: weightIncrement,
            SettingsKey.autoStartRest: true,
            SettingsKey.barWeight: barWeight,
            SettingsKey.availablePlates: platesString,
            SettingsKey.oneRepMaxFormula: OneRepMaxFormula.brzycki.rawValue,
            SettingsKey.bodyModel: BodyModel.male.rawValue,
            SettingsKey.appearance: AppearanceSetting.system.rawValue,
            SettingsKey.healthImportWeight: true,
            SettingsKey.healthSaveWeight: true,
            SettingsKey.healthSaveWorkouts: true,
            SettingsKey.goalWeight: 0.0,
        ])
    }
}
