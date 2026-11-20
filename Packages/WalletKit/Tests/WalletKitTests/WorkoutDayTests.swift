import Foundation
import SwiftData
import Testing
@testable import WalletData
import WalletDomain
@testable import WalletFeature

@MainActor
struct WorkoutDayTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let today = DayKey(year: 2026, month: 10, day: 5)

    private func day(_ value: Int, month: Int = 10) -> DayKey { DayKey(year: 2026, month: month, day: value) }

    @Test func markingTheSameDayTwiceReplacesItAndUnmarkingIsRepeatable() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = WorkoutDayUseCases(repository: repository)
        try await useCases.mark(today, minutes: 45, activity: .run, note: "  hills \n", today: today)
        var days = try await useCases.load()
        #expect(days == [WorkoutDay(day: today, minutes: 45, activity: .run, note: "hills", updatedAt: days[0].updatedAt)])

        try await useCases.mark(today, minutes: nil, activity: nil, note: "", today: today)
        days = try await useCases.load()
        #expect(days.count == 1)
        #expect(days.first?.minutes == nil)
        #expect(days.first?.activity == nil)
        #expect(days.first?.note == "")

        try await useCases.unmark(today)
        try await useCases.unmark(today)
        #expect(try await useCases.load().isEmpty)
    }

    @Test func exercisesAreSavedInListOrderOnceEachAndOnlyForActivitiesThatListThem() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = WorkoutDayUseCases(repository: repository)
        let saved = try await useCases.mark(today, minutes: 30, activity: .home,
                                            exercises: ["crunch", "  Wall  sit ", "Push-up", "Chest", "CRUNCH", " "],
                                            note: "", today: today)
        #expect(saved.exercises == ["Chest", "Push-up", "Crunch", "Wall sit"])
        #expect(try await useCases.load().first?.exercises == saved.exercises)

        let run = try await useCases.mark(today, minutes: 30, activity: .run, exercises: ["Squat"], note: "", today: today)
        #expect(run.exercises.isEmpty)
        #expect(try await useCases.load().first?.exercises == [])

        let unspecified = try await useCases.mark(today, minutes: nil, activity: nil, exercises: ["Squat"], note: "", today: today)
        #expect(unspecified.exercises == ["Squat"])

        await #expect(throws: WorkoutDayError.tooManyExercises) {
            try await useCases.mark(today, minutes: nil, activity: .gym,
                                    exercises: (0...WorkoutExercises.maximumPerDay).map { "Move \($0)" }, note: "", today: today)
        }
        await #expect(throws: WorkoutDayError.invalidExerciseName) {
            try await useCases.mark(today, minutes: nil, activity: .gym,
                                    exercises: [String(repeating: "a", count: WorkoutExercises.maximumNameLength + 1)],
                                    note: "", today: today)
        }
    }

    @Test func ownExercisesAreAddedOnceIgnoringCaseAndDeletingOneKeepsPastDays() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = WorkoutDayUseCases(repository: repository)
        #expect(try await useCases.addExercise("  wall   sit ") == "wall sit")
        #expect(try await useCases.addExercise("Wall Sit") == "wall sit")
        #expect(try await useCases.addExercise("push-UP") == "Push-up")
        #expect(try await useCases.addExercise("Bear crawl") == "Bear crawl")
        #expect(try await useCases.loadExercises() == ["Bear crawl", "wall sit"])
        for name in ["", "   ", String(repeating: "a", count: WorkoutExercises.maximumNameLength + 1)] {
            await #expect(throws: WorkoutDayError.invalidExerciseName) { try await useCases.addExercise(name) }
        }

        try await useCases.mark(today, minutes: nil, activity: .gym, exercises: ["wall sit"], note: "", today: today)
        try await useCases.deleteExercise("WALL SIT")
        #expect(try await useCases.loadExercises() == ["Bear crawl"])
        #expect(try await useCases.load().first?.exercises == ["wall sit"])
    }

    @Test func ownExercisesUploadedTwiceReadOnceAndDeleteTogether() async throws {
        let container = try WalletPersistence.makeContainer(configuration: .inMemory)
        let context = ModelContext(container)
        context.insert(WorkoutExerciseRecord(name: "Wall sit"))
        context.insert(WorkoutExerciseRecord(name: "wall sit"))
        try context.save()
        let store = WalletStore(modelContainer: container)
        #expect(try await store.fetchWorkoutExercises().count == 1)
        try await store.saveWorkoutExercise("WALL SIT")
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<WorkoutExerciseRecord>()) == 2)
        try await store.deleteWorkoutExercise("Wall Sit")
        #expect(try await store.fetchWorkoutExercises().isEmpty)
    }

    @Test func viewModelListsOwnExercisesAndShowsSavedExercisesAtOnce() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let now = today.date(in: calendar).addingTimeInterval(3600)
        let viewModel = WorkoutDaysViewModel(useCases: WorkoutDayUseCases(repository: repository),
                                             calendar: calendar, now: { now })
        await viewModel.observe()
        #expect(try await viewModel.addExercise("Wall sit") == "Wall sit")
        #expect(try await viewModel.addExercise("Bear crawl") == "Bear crawl")
        #expect(try await viewModel.addExercise("plank") == "Plank")
        #expect(viewModel.customExercises == ["Bear crawl", "Wall sit"])
        try await viewModel.mark(today, minutes: 20, activity: .home, exercises: ["Wall sit", "Plank"], note: "")
        #expect(viewModel.days[today]?.exercises == ["Plank", "Wall sit"])
        try await viewModel.deleteExercise("Wall sit")
        #expect(viewModel.customExercises == ["Bear crawl"])
    }

    @Test func rejectsFutureDaysOutOfRangeMinutesAndLongNotes() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = WorkoutDayUseCases(repository: repository)
        await #expect(throws: WorkoutDayError.futureDay) {
            try await useCases.mark(today.adding(days: 1, calendar: calendar), minutes: nil, activity: nil, note: "", today: today)
        }
        for minutes in [0, -5, WorkoutDay.maximumMinutes + 1] {
            await #expect(throws: WorkoutDayError.invalidMinutes) {
                try await useCases.mark(today, minutes: minutes, activity: .gym, note: "", today: today)
            }
        }
        await #expect(throws: WorkoutDayError.noteTooLong) {
            try await useCases.mark(today, minutes: 30, activity: nil, note: String(repeating: "a", count: 501), today: today)
        }
        #expect(try await useCases.load().isEmpty)
    }

    @Test func duplicateRowsFromAnotherDeviceReadAsTheNewestAndFoldOnSave() async throws {
        let container = try WalletPersistence.makeContainer(configuration: .inMemory)
        let context = ModelContext(container)
        context.insert(WorkoutDayRecord(day: WorkoutDay(day: today, minutes: 20, updatedAt: Date(timeIntervalSince1970: 100))))
        context.insert(WorkoutDayRecord(day: WorkoutDay(day: today, minutes: 60, activity: .swim,
                                                        updatedAt: Date(timeIntervalSince1970: 200))))
        try context.save()
        let store = WalletStore(modelContainer: container)
        #expect(try await store.fetchWorkoutDays().map(\.minutes) == [60])
        #expect(try await store.fetchWorkoutDays().map(\.activity) == [.swim])
        try await store.saveWorkoutDay(WorkoutDay(day: today, minutes: 30))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<WorkoutDayRecord>()) == 1)
        #expect(try await store.fetchWorkoutDays().map(\.minutes) == [30])
    }

    @Test func anActivityFromANewerVersionReadsAsOther() async throws {
        let container = try WalletPersistence.makeContainer(configuration: .inMemory)
        let context = ModelContext(container)
        let record = WorkoutDayRecord(day: WorkoutDay(day: today))
        record.activityValue = "climbing"
        context.insert(record)
        try context.save()
        #expect(try await WalletStore(modelContainer: container).fetchWorkoutDays().map(\.activity) == [.other])
    }

    @Test func workoutDaysStayOutOfWalletReset() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = WorkoutDayUseCases(repository: repository)
        try await useCases.mark(today, minutes: 30, activity: .walk, note: "", today: today)
        try await repository.resetWalletData()
        #expect(try await useCases.load().map(\.day) == [today])
    }

    @Test func summaryCountsElapsedDaysOfTheMonthAndTheCurrentStreak() {
        let days = [
            WorkoutDay(day: day(1), minutes: 30),
            WorkoutDay(day: day(3)),
            WorkoutDay(day: day(4), minutes: 45),
            WorkoutDay(day: day(30, month: 9), minutes: 90),
        ]
        let current = WorkoutSummary(days: days, month: day(1), today: today, calendar: calendar)
        #expect(current.workoutDays == 3)
        #expect(current.totalMinutes == 75)
        #expect(current.restDays == 2)
        // Today (the 5th) is not marked yet, so the run of the 3rd and 4th still counts.
        #expect(current.currentStreak == 2)

        let markedToday = WorkoutSummary(days: days + [WorkoutDay(day: today)], month: day(1), today: today, calendar: calendar)
        #expect(markedToday.currentStreak == 3)

        let brokenYesterday = WorkoutSummary(days: days, month: day(1), today: day(6), calendar: calendar)
        #expect(brokenYesterday.currentStreak == 0)

        let september = WorkoutSummary(days: days, month: day(1, month: 9), today: today, calendar: calendar)
        #expect(september.workoutDays == 1)
        #expect(september.restDays == 29)
        #expect(september.totalMinutes == 90)

        #expect(WorkoutSummary(days: days, month: day(1, month: 11), today: today, calendar: calendar).restDays == 0)
        #expect(WorkoutSummary(days: [], month: today, today: today, calendar: calendar).currentStreak == 0)
    }

    @Test func heatmapShadesByMinutesAndCountsTheLongestWorkoutRun() {
        #expect(WorkoutHeatmap.level(for: nil) == 0)
        #expect([nil, 10, 20, 21, 40, 41, 60, 61, 600].map { WorkoutHeatmap.level(for: WorkoutDay(day: today, minutes: $0)) }
                == [1, 1, 1, 2, 2, 3, 3, 4, 4])
        let days = [
            WorkoutDay(day: day(1), minutes: 50, activity: .cycle),
            WorkoutDay(day: day(2)),
            WorkoutDay(day: day(3), minutes: 10),
            WorkoutDay(day: day(20, month: 9), minutes: 30),
            WorkoutDay(day: DayKey(year: 2024, month: 1, day: 1), minutes: 300),
        ]
        let heatmap = WorkoutHeatmap(days: days, period: .pastYear, today: today, calendar: calendar)
        #expect(heatmap.workoutDays == 4)
        #expect(heatmap.restDays == 361)
        #expect(heatmap.totalMinutes == 90)
        #expect(heatmap.longestStreak == 3)
        let first = heatmap.weeks.flatMap { $0 }.compactMap { $0 }.first { $0.day == day(1) }
        #expect(first?.level == 3)
        #expect(first?.minutes == 50)
        #expect(first?.activity == .cycle)
    }

    @Test func sharedGridLaysOutTheSameYearForBothTrackers() {
        let grid = DayGrid(period: .pastYear, today: today, calendar: calendar)
        #expect(grid.days.count == 365)
        #expect(grid.days.first == grid.first)
        #expect(grid.days.last == today)
        #expect(grid.days == grid.weeks.flatMap { $0 }.compactMap { $0 })
        let workouts = WorkoutHeatmap(days: [], period: .pastYear, today: today, calendar: calendar)
        let drinking = DrinkingHeatmap(days: [], period: .pastYear, today: today, calendar: calendar)
        #expect(workouts.monthLabels == grid.monthLabels)
        #expect(workouts.weeks.map { $0.map { $0?.day } } == drinking.weeks.map { $0.map { $0?.day } })
        #expect(grid.longestRun { $0.day == 1 } == 1)
        #expect(grid.longestRun { _ in true } == 365)
    }

    @Test func editorStepsInFiveMinutesAndSnapsOddValues() {
        #expect(WorkoutDayEditorView.stepUp(0) == 5)
        #expect(WorkoutDayEditorView.stepUp(42) == 45)
        #expect(WorkoutDayEditorView.stepUp(45) == 50)
        #expect(WorkoutDayEditorView.stepUp(WorkoutDay.maximumMinutes) == WorkoutDay.maximumMinutes)
        #expect(WorkoutDayEditorView.stepDown(5) == 0)
        #expect(WorkoutDayEditorView.stepDown(42) == 40)
        #expect(WorkoutDayEditorView.stepDown(45) == 40)
        #expect(WorkoutDayEditorView.stepDown(3) == 0)
        #expect(workoutDurationText(minutes: 45) == "45 min")
        #expect(workoutDurationText(minutes: 60) == "1 hr")
        #expect(workoutDurationText(minutes: 95) == "1 hr 35 min")
    }

    @Test func viewModelReflectsMarksPagesYearsAndStopsAtTheCurrentMonth() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let now = today.date(in: calendar).addingTimeInterval(3600)
        let viewModel = WorkoutDaysViewModel(useCases: WorkoutDayUseCases(repository: repository),
                                             calendar: calendar, now: { now })
        await viewModel.observe()
        #expect(viewModel.days.isEmpty)
        #expect(!viewModel.isLoading)
        #expect(!viewModel.canShowEarlierYear)

        try await viewModel.mark(today, minutes: 40, activity: .yoga, note: "")
        #expect(viewModel.days[today]?.activity == .yoga)
        #expect(viewModel.summary.workoutDays == 1)
        #expect(viewModel.summary.currentStreak == 1)
        #expect(viewModel.heatmap.totalMinutes == 40)

        #expect(!viewModel.canShowNextMonth)
        viewModel.showMonth(offset: 1)
        #expect(viewModel.month == day(1))
        viewModel.showMonth(offset: -1)
        #expect(viewModel.month == day(1, month: 9))
        #expect(viewModel.summary.workoutDays == 0)
        viewModel.showCurrentMonth()
        #expect(viewModel.month == day(1))

        try await viewModel.mark(DayKey(year: 2025, month: 3, day: 1), minutes: nil, activity: nil, note: "")
        viewModel.showYear(offset: -1)
        #expect(viewModel.heatmapPeriod == .year(2025))
        #expect(!viewModel.canShowEarlierYear)
        viewModel.showYear(offset: 1)
        #expect(viewModel.heatmapPeriod == .pastYear)

        try await viewModel.unmark(today)
        #expect(viewModel.days[today] == nil)
    }
}
