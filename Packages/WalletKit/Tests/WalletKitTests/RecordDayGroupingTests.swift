import Foundation
import Testing
import WalletDomain
@testable import WalletFeature

struct RecordDayGroupingTests {
    /// Noon UTC keeps the fixture away from a midnight boundary in the test runner's calendar.
    private let start = Date(timeIntervalSince1970: 1_704_110_400) // 2024-01-01 12:00 UTC

    private func result(amount: Decimal = 10, day: Int = 0, hour: Int = 0,
                        kind: RecordKind = .expense, currency: String = "USD") -> RecordSearchResult {
        var draft = RecordDraft()
        draft.kind = kind
        draft.accountID = UUID()
        draft.destinationAccountID = kind == .transfer ? UUID() : nil
        draft.amount = amount
        draft.date = start.addingTimeInterval(Double(day) * 86400 + Double(hour) * 3600)
        return RecordSearchResult(record: WalletRecord(id: UUID(), draft: draft, currencyCode: currency), score: 0)
    }

    @Test func groupsConsecutiveRecordsByCalendarDayPreservingOrder() {
        let first = result(day: 0, hour: 2)
        let second = result(day: 0, hour: 1)
        let third = result(day: 1)
        let sections = RecordDayGrouping.sections(for: [first, second, third])

        #expect(sections.count == 2)
        #expect(sections[0].results.map(\.id) == [first.id, second.id])
        #expect(sections[1].results.map(\.id) == [third.id])
    }

    @Test func dayNetSubtractsExpensesAndAddsIncome() {
        let sections = RecordDayGrouping.sections(for: [
            result(amount: 30, kind: .expense),
            result(amount: 100, kind: .income),
            result(amount: 20, kind: .expense),
        ])

        #expect(sections.count == 1)
        #expect(sections[0].net == 50)
        #expect(sections[0].currencyCode == "USD")
    }

    @Test func transfersDoNotCountTowardTheDayNet() {
        let sections = RecordDayGrouping.sections(for: [
            result(amount: 40, kind: .expense),
            result(amount: 500, kind: .transfer),
        ])

        #expect(sections[0].net == -40)
        #expect(sections[0].currencyCode == "USD")
    }

    @Test func daysHoldingOnlyTransfersReportNoNet() {
        let sections = RecordDayGrouping.sections(for: [result(amount: 500, kind: .transfer)])

        #expect(sections.count == 1)
        #expect(sections[0].net == nil)
        #expect(sections[0].currencyCode == nil)
    }

    /// Unlike currencies are never added together, so a mixed day states no total at all.
    @Test func mixedCurrencyDaysReportNoNet() {
        let sections = RecordDayGrouping.sections(for: [
            result(amount: 10, kind: .expense, currency: "USD"),
            result(amount: 10, kind: .expense, currency: "EUR"),
        ])

        #expect(sections.count == 1)
        #expect(sections[0].net == nil)
        #expect(sections[0].currencyCode == nil)
    }

    @Test func dayHeadersApplyToDateAndRelevanceOrderButNotAmountOrder() {
        #expect(RecordDayGrouping.groups(.newest, hasText: false))
        #expect(RecordDayGrouping.groups(.oldest, hasText: true))
        #expect(RecordDayGrouping.groups(.relevance, hasText: false))
        // Search results get day headers too.
        #expect(RecordDayGrouping.groups(.relevance, hasText: true))
        #expect(!RecordDayGrouping.groups(.largest, hasText: false))
        #expect(!RecordDayGrouping.groups(.smallest, hasText: false))

        // Only ranked search results need their days put back in date order.
        #expect(RecordDayGrouping.daysByDate(.relevance, hasText: true))
        #expect(!RecordDayGrouping.daysByDate(.relevance, hasText: false))
        #expect(!RecordDayGrouping.daysByDate(.oldest, hasText: true))
    }

    /// Ranked results arrive with days interleaved. Grouped, the days run newest first like the
    /// normal ledger, and each day still leads with its best match.
    @Test func searchResultsGroupNewestDayFirstWithTheBestMatchFirstWithinADay() {
        func ranked(day: Int, score: Int) -> RecordSearchResult {
            let base = result(day: day)
            return RecordSearchResult(record: base.record, score: score)
        }
        let strongOld = ranked(day: 0, score: 90)
        let newest = ranked(day: 2, score: 60)
        let weakOld = ranked(day: 0, score: 30)
        let middle = ranked(day: 1, score: 20)

        let sections = RecordDayGrouping.sections(for: [strongOld, newest, weakOld, middle], newestDayFirst: true)

        #expect(sections.map(\.date) == sections.map(\.date).sorted(by: >))
        #expect(sections.map { $0.results.map(\.id) } == [[newest.id], [middle.id], [strongOld.id, weakOld.id]])
    }
}
