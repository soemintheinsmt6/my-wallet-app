import Foundation
import SwiftData
import Testing
@testable import WalletData
import WalletDomain
import WalletFeature

@MainActor
struct DrinkingDayTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let today = DayKey(year: 2026, month: 10, day: 5)

    @Test func dayKeyRoundTripsItsStoredFormAndOrdersByDate() {
        let key = DayKey(year: 2026, month: 3, day: 9)
        #expect(key.rawValue == "2026-03-09")
        #expect(DayKey(rawValue: "2026-03-09") == key)
        #expect(DayKey(rawValue: "2026-13-01") == nil)
        #expect(DayKey(rawValue: "garbage") == nil)
        #expect(DayKey(year: 2025, month: 12, day: 31) < key)
        #expect(DayKey(key.date(in: calendar), calendar: calendar) == key)
    }

    @Test func markingTheSameDayTwiceReplacesItAndUnmarkingIsRepeatable() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = DrinkingDayUseCases(repository: repository)
        try await useCases.mark(today, drinks: 2, note: "  dinner \n", today: today)
        try await useCases.mark(today, drinks: nil, note: "", today: today)
        let days = try await useCases.load()
        #expect(days.count == 1)
        #expect(days.first?.drinks == nil)
        #expect(days.first?.note == "")
        try await useCases.unmark(today)
        try await useCases.unmark(today)
        #expect(try await useCases.load().isEmpty)
    }

    @Test func rejectsFutureDaysOutOfRangeCountsAndLongNotes() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = DrinkingDayUseCases(repository: repository)
        await #expect(throws: DrinkingDayError.futureDay) {
            try await useCases.mark(today.adding(days: 1, calendar: calendar), drinks: nil, note: "", today: today)
        }
        for drinks in [0, -1, DrinkingDay.maximumDrinks + 1] {
            await #expect(throws: DrinkingDayError.invalidDrinks) {
                try await useCases.mark(today, drinks: drinks, note: "", today: today)
            }
        }
        await #expect(throws: DrinkingDayError.noteTooLong) {
            try await useCases.mark(today, drinks: 1, note: String(repeating: "a", count: 501), today: today)
        }
        #expect(try await useCases.load().isEmpty)
    }

    @Test func duplicateRowsFromAnotherDeviceReadAsTheNewestAndFoldOnSave() async throws {
        let container = try WalletPersistence.makeContainer(configuration: .inMemory)
        let context = ModelContext(container)
        context.insert(DrinkingDayRecord(day: DrinkingDay(day: today, drinks: 1, updatedAt: Date(timeIntervalSince1970: 100))))
        context.insert(DrinkingDayRecord(day: DrinkingDay(day: today, drinks: 3, updatedAt: Date(timeIntervalSince1970: 200))))
        try context.save()
        let store = WalletStore(modelContainer: container)
        #expect(try await store.fetchDrinkingDays().map(\.drinks) == [3])
        try await store.saveDrinkingDay(DrinkingDay(day: today, drinks: 4))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<DrinkingDayRecord>()) == 1)
        #expect(try await store.fetchDrinkingDays().map(\.drinks) == [4])
    }

    @Test func summaryCountsOnlyElapsedDaysOfTheMonth() {
        let days = [
            DrinkingDay(day: DayKey(year: 2026, month: 10, day: 1), drinks: 2),
            DrinkingDay(day: DayKey(year: 2026, month: 10, day: 3)),
            DrinkingDay(day: DayKey(year: 2026, month: 9, day: 30), drinks: 5),
        ]
        let current = DrinkingSummary(days: days, month: DayKey(year: 2026, month: 10, day: 1), today: today, calendar: calendar)
        #expect(current.drinkingDays == 2)
        #expect(current.totalDrinks == 2)
        #expect(current.alcoholFreeDays == 3)
        #expect(current.daysSinceLastDrink == 2)

        let september = DrinkingSummary(days: days, month: DayKey(year: 2026, month: 9, day: 1), today: today, calendar: calendar)
        #expect(september.drinkingDays == 1)
        #expect(september.alcoholFreeDays == 29)

        let future = DrinkingSummary(days: days, month: DayKey(year: 2026, month: 11, day: 1), today: today, calendar: calendar)
        #expect(future.alcoholFreeDays == 0)

        #expect(DrinkingSummary(days: [], month: today, today: today, calendar: calendar).daysSinceLastDrink == nil)
    }

    @Test func pastYearHeatmapLaysOutWeeksFromTheFirstWeekdayAndEndsToday() {
        // Sunday-first; 2025-10-06 is a Monday, so the first column has one leading blank.
        let heatmap = DrinkingHeatmap(days: [], period: .pastYear, today: today, calendar: calendar)
        #expect(heatmap.first == DayKey(year: 2025, month: 10, day: 6))
        #expect(heatmap.last == today)
        #expect(heatmap.weeks.count == 53)
        #expect(heatmap.weeks.allSatisfy { $0.count == 7 })
        #expect(heatmap.weeks[0][0] == nil)
        #expect(heatmap.weeks[0][1]?.day == heatmap.first)
        #expect(heatmap.weeks[52][1]?.day == today)
        #expect(heatmap.weeks[52][2] == nil)
        #expect(heatmap.weeks.flatMap { $0 }.compactMap { $0 }.count == 365)
        #expect(heatmap.monthLabels.count == 13)
        #expect(heatmap.monthLabels.first?.week == 0)
        #expect(heatmap.monthLabels.first?.month == DayKey(year: 2025, month: 10, day: 1))
        #expect(heatmap.monthLabels.last?.month == DayKey(year: 2026, month: 10, day: 1))
    }

    @Test func calendarYearHeatmapDropsACrampedFirstMonthLabel() {
        let full = DrinkingHeatmap(days: [], period: .year(2025), today: today, calendar: calendar)
        #expect(full.first == DayKey(year: 2025, month: 1, day: 1))
        #expect(full.last == DayKey(year: 2025, month: 12, day: 31))
        #expect(full.monthLabels.map(\.month.month) == Array(1...12))
        // Starting on 2025-10-28 leaves October's label one column before November's.
        let cramped = DrinkingHeatmap(days: [], period: .pastYear, today: DayKey(year: 2026, month: 10, day: 27), calendar: calendar)
        #expect(cramped.monthLabels.first?.month == DayKey(year: 2025, month: 11, day: 1))
    }

    @Test func heatmapShadesByDrinksAndCountsTheLongestAlcoholFreeRun() {
        #expect(DrinkingHeatmap.level(for: nil) == 0)
        #expect([nil, 1, 2, 3, 4, 5, 6, 7, 99].map { DrinkingHeatmap.level(for: DrinkingDay(day: today, drinks: $0)) }
                == [1, 1, 1, 2, 2, 3, 3, 4, 4])
        let days = [
            DrinkingDay(day: DayKey(year: 2026, month: 10, day: 1), drinks: 3),
            DrinkingDay(day: DayKey(year: 2026, month: 10, day: 3)),
            DrinkingDay(day: DayKey(year: 2024, month: 1, day: 1), drinks: 9),
        ]
        let heatmap = DrinkingHeatmap(days: days, period: .pastYear, today: today, calendar: calendar)
        #expect(heatmap.drinkingDays == 2)
        #expect(heatmap.totalDrinks == 3)
        #expect(heatmap.alcoholFreeDays == 363)
        #expect(heatmap.longestAlcoholFreeStreak == 360)
        let october = heatmap.weeks.flatMap { $0 }.compactMap { $0 }.first { $0.day == days[0].day }
        #expect(october?.level == 2)
        #expect(october?.drinks == 3)
    }

    @Test func viewModelPagesYearsBackToTheEarliestMarkedDay() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let now = today.date(in: calendar).addingTimeInterval(3600)
        let viewModel = DrinkingDaysViewModel(useCases: DrinkingDayUseCases(repository: repository),
                                              calendar: calendar, now: { now })
        await viewModel.observe()
        #expect(viewModel.heatmapPeriod == .pastYear)
        #expect(!viewModel.canShowEarlierYear)
        #expect(!viewModel.canShowLaterYear)

        try await viewModel.mark(DayKey(year: 2024, month: 5, day: 1), drinks: 1, note: "")
        viewModel.showYear(offset: -1)
        #expect(viewModel.heatmapPeriod == .year(2025))
        viewModel.showYear(offset: -1)
        #expect(viewModel.heatmapPeriod == .year(2024))
        #expect(viewModel.heatmap.drinkingDays == 1)
        #expect(!viewModel.canShowEarlierYear)
        viewModel.showYear(offset: -1)
        #expect(viewModel.heatmapPeriod == .year(2024))
        viewModel.showYear(offset: 1)
        viewModel.showYear(offset: 1)
        #expect(viewModel.heatmapPeriod == .pastYear)
        #expect(!viewModel.canShowLaterYear)
    }

    @Test func viewModelReflectsMarksAndStopsAtTheCurrentMonth() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let now = today.date(in: calendar).addingTimeInterval(3600)
        let viewModel = DrinkingDaysViewModel(useCases: DrinkingDayUseCases(repository: repository),
                                              calendar: calendar, now: { now })
        await viewModel.observe()
        #expect(viewModel.days.isEmpty)
        #expect(!viewModel.isLoading)

        try await viewModel.mark(today, drinks: 2, note: "")
        #expect(viewModel.days[today]?.drinks == 2)
        #expect(viewModel.summary.drinkingDays == 1)
        #expect(viewModel.summary.daysSinceLastDrink == 0)

        #expect(!viewModel.canShowNextMonth)
        viewModel.showMonth(offset: 1)
        #expect(viewModel.month == DayKey(year: 2026, month: 10, day: 1))
        viewModel.showMonth(offset: -1)
        #expect(viewModel.month == DayKey(year: 2026, month: 9, day: 1))
        #expect(viewModel.summary.drinkingDays == 0)
        viewModel.showCurrentMonth()
        #expect(viewModel.month == DayKey(year: 2026, month: 10, day: 1))

        try await viewModel.unmark(today)
        #expect(viewModel.days.isEmpty)
    }
}
