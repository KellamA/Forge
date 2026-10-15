import Foundation
import SwiftData
import Testing
@testable import Forge

struct OneRepMaxTests {
    @Test func brzyckiMatchesClassicExample() {
        // 185 × 6 → ~215 lb
        let e = OneRepMax.estimate(weight: 185, reps: 6, formula: .brzycki)!
        #expect(abs(e - 214.84) < 0.1)
    }

    @Test func epleyAndSingles() {
        #expect(abs(OneRepMax.estimate(weight: 200, reps: 10, formula: .epley)! - 266.67) < 0.1)
        #expect(OneRepMax.estimate(weight: 315, reps: 1, formula: .blended) == 315)
    }

    @Test func rejectsUnreliableInput() {
        #expect(OneRepMax.estimate(weight: 0, reps: 5, formula: .brzycki) == nil)
        #expect(OneRepMax.estimate(weight: 100, reps: 25, formula: .brzycki) == nil)
    }

    @Test(arguments: OneRepMaxFormula.allCases)
    func inverseRoundTrips(formula: OneRepMaxFormula) {
        let max = OneRepMax.estimate(weight: 225, reps: 5, formula: formula)!
        let back = OneRepMax.weight(forReps: 5, oneRepMax: max, formula: formula)
        #expect(abs(back - 225) < 0.01)
    }
}

struct ScheduleEngineTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func day(_ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 9))!
    }

    @Test func rotationWithoutRestJustUsesPosition() {
        let r = ScheduleEngine.rotationSlot(kinds: [.workout, .workout, .workout], position: 1,
                                            lastAdvance: day(12), now: day(15), calendar: calendar)
        #expect(r == .init(index: 1, isRestDay: false))
    }

    @Test func restSlotFollowsTrainingDay() {
        // Push, Pull, Legs, Rest. Legs finished Monday (12th) → position 3 (Rest).
        let kinds: [DayKind] = [.workout, .workout, .workout, .rest]
        // Same day: rest is up next but today isn't a rest day.
        #expect(ScheduleEngine.rotationSlot(kinds: kinds, position: 3, lastAdvance: day(12), now: day(12), calendar: calendar)
                == .init(index: 3, isRestDay: false))
        // Next day: rest day.
        #expect(ScheduleEngine.rotationSlot(kinds: kinds, position: 3, lastAdvance: day(12), now: day(13), calendar: calendar)
                == .init(index: 3, isRestDay: true))
        // Day after: rest is used up, Push is next.
        #expect(ScheduleEngine.rotationSlot(kinds: kinds, position: 3, lastAdvance: day(12), now: day(14), calendar: calendar)
                == .init(index: 0, isRestDay: false))
    }

    @Test func consecutiveRestSlotsEachTakeADay() {
        let kinds: [DayKind] = [.workout, .rest, .rest]
        #expect(ScheduleEngine.rotationSlot(kinds: kinds, position: 1, lastAdvance: day(10), now: day(12), calendar: calendar)
                == .init(index: 2, isRestDay: true))
        #expect(ScheduleEngine.rotationSlot(kinds: kinds, position: 1, lastAdvance: day(10), now: day(13), calendar: calendar)
                == .init(index: 0, isRestDay: false))
    }

    @Test func advancingWraps() {
        #expect(ScheduleEngine.position(afterCompleting: 2, count: 3) == 0)
        #expect(ScheduleEngine.position(afterCompleting: 0, count: 3) == 1)
    }

    @Test func weeklyLookup() {
        // Oct 14 2026 is a Wednesday (weekday 4).
        let weekdays = [[2, 5], [4], [7]]
        #expect(ScheduleEngine.weeklyIndices(on: day(14), weekdays: weekdays, calendar: calendar) == [1])
        let next = ScheduleEngine.nextWeeklyDate(after: day(14), weekdays: weekdays, calendar: calendar)
        #expect(next?.1 == [0]) // Thursday
    }
}

struct PlateCalculatorTests {
    @Test func loadsStandardWeights() {
        let result = PlateCalculatorView.load(target: 225, bar: 45, plates: [45, 35, 25, 10, 5, 2.5])
        #expect(result.perSide == [45, 45])
        #expect(result.achieved == 225)
        // 71.25 lb per side can't be loaded exactly with 2.5s; it rounds down to the closest load.
        let odd = PlateCalculatorView.load(target: 187.5, bar: 45, plates: [45, 35, 25, 10, 5, 2.5])
        #expect(odd.perSide == [45, 25])
        #expect(odd.achieved == 185)
    }
}

struct CatalogTests {
    @Test func catalogLoads() {
        #expect(ExerciseCatalog.shared.all.count > 850)
        #expect(ExerciseCatalog.shared.byID["Barbell_Bench_Press_-_Medium_Grip"]?.name == "Bench Press (Barbell)")
    }

    @Test func everyTemplateExerciseExists() {
        for template in SplitTemplate.all {
            for day in template.days {
                for lift in day.lifts {
                    #expect(ExerciseCatalog.shared.byID[lift.id] != nil, "\(template.name): missing \(lift.id)")
                }
            }
        }
    }

    @Test func everyMuscleIsDrawable() {
        for model in BodyModel.allCases {
            let front = BodyMapStore.shared.figure(model, .front)
            let back = BodyMapStore.shared.figure(model, .back)
            #expect(front != nil && back != nil)
            let drawn = Set((front?.regions ?? []).compactMap(\.muscle) + (back?.regions ?? []).compactMap(\.muscle))
            for muscle in Muscle.allCases where muscle != .abductors {
                #expect(drawn.contains(muscle), "\(model) is missing \(muscle)")
            }
        }
    }

    @Test func pathParser() {
        let path = SVGPath.parse("M 0 0 L 10 0 L 10 20 Z")
        #expect(path.boundingRect == CGRect(x: 0, y: 0, width: 10, height: 20))
    }
}

@MainActor
struct WidgetSnapshotTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func day(_ d: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
    }

    @Test func weeklySplitTimeline() throws {
        let schema = Schema(ForgeSchema.models)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let split = WorkoutSplit(name: "Upper Lower", mode: .weekly)
        let push = SplitDay(name: "Push", kind: .workout, order: 0)
        push.weekdays = [4] // Wednesday
        let pull = SplitDay(name: "Pull", kind: .workout, order: 1)
        pull.weekdays = [6] // Friday
        let bench = PlannedExercise(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", name: "Bench Press", order: 0)
        context.insert(split)
        context.insert(push)
        context.insert(pull)
        context.insert(bench)
        push.split = split
        pull.split = split
        bench.day = push

        // Monday and Wednesday morning (Push) are done; it's Wednesday Oct 14.
        let monday = WorkoutSession(name: "Pull", startedAt: day(12))
        monday.endedAt = day(12, hour: 10)
        let wednesday = WorkoutSession(name: "Push", startedAt: day(14, hour: 7))
        wednesday.endedAt = day(14, hour: 8)
        wednesday.splitDayID = push.id
        context.insert(monday)
        context.insert(wednesday)
        let history = HistorySnapshot(sessions: [monday, wednesday], cardio: [], formula: .brzycki)

        let snapshot = WidgetSync.makeSnapshot(split: split, history: history, goal: 2, library: ExerciseLibrary(),
                                               now: day(14), calendar: calendar) { $0.name == "Push" ? "push.png" : nil }
        #expect(snapshot.weeklyGoal == 2)
        #expect(snapshot.entries.count == 8)

        let today = snapshot.entries[0]
        #expect(today.date == calendar.startOfDay(for: day(14)))
        #expect(today.status == .doneToday)
        #expect(today.day?.name == "Pull")
        #expect(today.dayDate == calendar.startOfDay(for: day(16)))
        #expect(today.sessionsThisWeek == 2)
        #expect(today.streak == 1)

        let thursday = snapshot.entries[1]
        #expect(thursday.status == .rest)
        #expect(thursday.day?.name == "Pull")

        let friday = snapshot.entries[2]
        #expect(friday.status == .today)
        #expect(friday.day?.name == "Pull")

        // Next Wednesday is Push again, with its muscles and body map.
        let nextWednesday = snapshot.entries[7]
        #expect(nextWednesday.status == .today)
        #expect(nextWednesday.day?.exerciseCount == 1)
        #expect(nextWednesday.day?.muscles.first == "Chest")
        #expect(nextWednesday.day?.bodyMapFile == "push.png")

        // Sunday starts a new week: the count resets but last week's streak carries over.
        let sunday = snapshot.entries[4]
        #expect(sunday.sessionsThisWeek == 0)
        #expect(sunday.streak == 1)

        #expect(snapshot.entry(at: day(17, hour: 12))?.date == calendar.startOfDay(for: day(17)))
    }

    @Test func noSplitAndRoundTrip() throws {
        let snapshot = WidgetSync.makeSnapshot(split: nil, history: .empty, goal: 4, library: ExerciseLibrary(),
                                               now: day(14), calendar: calendar)
        #expect(snapshot.entries.allSatisfy { $0.status == .noSplit && $0.day == nil })
        let data = try WidgetShared.encoder.encode(snapshot)
        #expect(try WidgetShared.decoder.decode(WidgetSnapshot.self, from: data) == snapshot)
    }
}
