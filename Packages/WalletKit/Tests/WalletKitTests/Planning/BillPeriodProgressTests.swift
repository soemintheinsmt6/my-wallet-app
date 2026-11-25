import Foundation
import Testing
import WalletDomain

struct BillPeriodProgressTests {
    private let march = DateInterval(start: Date(timeIntervalSince1970: 1_709_251_200), // 2024-03-01 UTC
                                     end: Date(timeIntervalSince1970: 1_711_929_600))   // 2024-04-01 UTC
    private func day(_ value: Int, month: Int = 3) -> Date {
        var components = DateComponents(year: 2024, month: month, day: value)
        components.timeZone = .gmt
        return Calendar(identifier: .gregorian).date(from: components)!
    }
    private func bill(_ amount: Decimal, due: Date, rule: RecurrenceRule? = nil, paid: Int = 0,
                      currency: String = "USD") -> BillReminder {
        var bill = BillReminder(name: "Bill", amount: amount, currencyCode: currency, dueDate: due, recurrence: rule)
        bill.nextIndex = paid
        return bill
    }

    @Test func countsEachOccurrenceDueInThePeriodAndThosePaidInOrder() {
        let weekly = RecurrenceRule(frequency: .weekly, timeZoneIdentifier: "UTC")
        let monthly = RecurrenceRule(frequency: .monthly, timeZoneIdentifier: "UTC")
        let bills = [
            // Mar 4, 11, 18, 25 fall in March; Feb 26 was index 0. Paid through Mar 11.
            bill(10, due: day(26, month: 2), rule: weekly, paid: 3),
            // Rent on the 1st, March is index 2, not yet paid.
            bill(500, due: day(1, month: 1), rule: monthly, paid: 2),
            // A one-off paid in March.
            bill(40, due: day(20), paid: 1),
            // Due in April: not counted.
            bill(99, due: day(2, month: 4))
        ]
        let progress = BillPeriodProgress(bills: bills, in: march)
        #expect(progress.dueCount == 6)
        #expect(progress.paidCount == 3)
        #expect(progress.dueAmount == 580)
        #expect(progress.paidAmount == 60)
        #expect(progress.currencyCode == "USD")
        #expect(progress.fraction == 0.5)
    }

    @Test func leavesAmountsOutWhenBillsSpanCurrenciesAndIsEmptyWithNothingDue() {
        let mixed = BillPeriodProgress(bills: [bill(10, due: day(5)), bill(20, due: day(6), currency: "EUR")], in: march)
        #expect(mixed.dueCount == 2)
        #expect(mixed.dueAmount == nil)
        #expect(mixed.paidAmount == nil)
        let none = BillPeriodProgress(bills: [bill(10, due: day(5, month: 5))], in: march)
        #expect(none.dueCount == 0)
        #expect(none.fraction == 0)
    }
}
