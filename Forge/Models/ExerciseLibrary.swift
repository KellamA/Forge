import Foundation
import Observation

/// A read-only description of an exercise, from the bundled catalog or a custom exercise.
struct ExerciseInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let primary: [Muscle]
    let secondary: [Muscle]
    let equipment: Equipment
    let category: ExerciseCategory
    let tracking: TrackingType
    let instructions: [String]
    let level: String?
    let mechanic: String?
    let aliases: [String]
    let isPopular: Bool
    let isCustom: Bool

    var isCompound: Bool { mechanic == "compound" }

    var allMuscles: [Muscle] { primary + secondary }

    /// Intensities for the body map: primary muscles full strength, secondary muscles lighter.
    var muscleIntensities: [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for m in secondary { result[m] = 0.45 }
        for m in primary { result[m] = 1.0 }
        return result
    }

    var subtitle: String {
        let muscles = primary.map(\.displayName).joined(separator: ", ")
        return muscles.isEmpty ? equipment.displayName : "\(muscles) · \(equipment.displayName)"
    }

    fileprivate var searchText: String {
        ([name] + aliases).joined(separator: " ").lowercased()
    }
}

/// The bundled exercise catalog (free-exercise-db, public domain, plus curated additions).
final class ExerciseCatalog: @unchecked Sendable {
    static let shared = ExerciseCatalog()

    let all: [ExerciseInfo]
    let byID: [String: ExerciseInfo]

    private struct Entry: Decodable {
        let id: String
        let n: String
        let p: [String]
        let s: [String]
        let e: String
        let c: String
        let t: String
        let i: [String]
        let l: String?
        let m: String?
        let a: [String]?
        let pop: Int?
    }

    private init() {
        var items: [ExerciseInfo] = []
        if let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let entries = try? JSONDecoder().decode([Entry].self, from: data) {
            items = entries.map { e in
                ExerciseInfo(
                    id: e.id,
                    name: e.n,
                    primary: e.p.compactMap(Muscle.init(rawValue:)),
                    secondary: e.s.compactMap(Muscle.init(rawValue:)),
                    equipment: Equipment(rawValue: e.e) ?? .other,
                    category: ExerciseCategory(rawValue: e.c) ?? .strength,
                    tracking: TrackingType(rawValue: e.t) ?? .weightReps,
                    instructions: e.i,
                    level: e.l,
                    mechanic: e.m,
                    aliases: e.a ?? [],
                    isPopular: e.pop == 1,
                    isCustom: false
                )
            }
        }
        all = items
        byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

struct ExerciseFilter: Equatable {
    var query: String = ""
    var muscles: Set<Muscle> = []
    var equipment: Set<Equipment> = []
    var categories: Set<ExerciseCategory> = []
    var favoritesOnly = false
    var customOnly = false

    var isActive: Bool {
        !query.isEmpty || !muscles.isEmpty || !equipment.isEmpty || !categories.isEmpty || favoritesOnly || customOnly
    }
}

/// Built-in catalog merged with the user's custom exercises.
@MainActor
@Observable
final class ExerciseLibrary {
    private(set) var custom: [ExerciseInfo] = []
    private(set) var all: [ExerciseInfo] = ExerciseCatalog.shared.all
    private var customByID: [String: ExerciseInfo] = [:]

    func update(custom exercises: [CustomExercise]) {
        let infos = exercises.map(\.info).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        custom = infos
        customByID = Dictionary(infos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        all = (ExerciseCatalog.shared.all + infos).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func exercise(id: String) -> ExerciseInfo? {
        customByID[id] ?? ExerciseCatalog.shared.byID[id]
    }

    /// Filters and ranks exercises. With a query, exact and prefix matches and popular lifts rank first.
    func search(_ filter: ExerciseFilter, favorites: Set<String>) -> [ExerciseInfo] {
        let terms = filter.query.lowercased().split(separator: " ").map(String.init)
        var results = all.filter { ex in
            if filter.favoritesOnly && !favorites.contains(ex.id) { return false }
            if filter.customOnly && !ex.isCustom { return false }
            if !filter.muscles.isEmpty && filter.muscles.isDisjoint(with: ex.primary) { return false }
            if !filter.equipment.isEmpty && !filter.equipment.contains(ex.equipment) { return false }
            if !filter.categories.isEmpty && !filter.categories.contains(ex.category) { return false }
            if !terms.isEmpty {
                let text = ex.searchText
                return terms.allSatisfy { text.contains($0) }
            }
            return true
        }
        if !terms.isEmpty {
            let q = filter.query.lowercased()
            results.sort { a, b in
                let sa = score(a, query: q, favorites: favorites)
                let sb = score(b, query: q, favorites: favorites)
                if sa != sb { return sa > sb }
                return a.name.count < b.name.count
            }
        }
        return results
    }

    private func score(_ ex: ExerciseInfo, query: String, favorites: Set<String>) -> Int {
        let name = ex.name.lowercased()
        var s = 0
        if name == query { s += 100 }
        if name.hasPrefix(query) { s += 40 }
        if ex.aliases.contains(where: { $0.lowercased() == query }) { s += 60 }
        if ex.isPopular { s += 30 }
        if ex.isCustom { s += 25 }
        if favorites.contains(ex.id) { s += 35 }
        if ex.category == .stretching { s -= 10 }
        return s
    }
}
