import Foundation
import Testing
@testable import WalletFeature

struct RecordAmountDisplayTests {
    @Test func groupsWithoutRoundingOrDiscardingDraftDecimals() {
        let locale = Locale(identifier: "en_US")
        #expect(RecordAmountDisplay.grouped("", locale: locale) == "0")
        #expect(RecordAmountDisplay.grouped("1234567.00", locale: locale) == "1,234,567.00")
        #expect(RecordAmountDisplay.grouped("1234.", locale: locale) == "1,234.")
        #expect(RecordAmountDisplay.grouped("123456789012345678.12345678", locale: locale) == "123,456,789,012,345,678.12345678")
        #expect(RecordAmountDisplay.grouped("invalid", locale: locale) == "invalid")
    }

    @Test func respectsLocaleSeparatorsAndGroupingSizes() {
        #expect(RecordAmountDisplay.grouped("1234567,50", locale: Locale(identifier: "de_DE")) == "1.234.567,50")
        #expect(RecordAmountDisplay.grouped("1234567.50", locale: Locale(identifier: "en_IN")) == "12,34,567.50")
    }

    @Test func keepsTheSignOnNegativeBalances() {
        let locale = Locale(identifier: "en_US")
        #expect(RecordAmountDisplay.grouped("-1234567.89", locale: locale) == "-1,234,567.89")
        #expect(RecordAmountDisplay.grouped("+1234", locale: locale) == "+1,234")
        #expect(RecordAmountDisplay.grouped("-", locale: locale) == "-")
    }

    @Test func groupsStoredAmountsForDisplay() {
        let locale = Locale(identifier: "en_US")
        #expect(RecordAmountDisplay.grouped(Decimal(string: "1234567.5")!, locale: locale) == "1,234,567.5")
        #expect(RecordAmountDisplay.grouped(Decimal(0), locale: locale) == "0")
    }

    @Test func ungroupsBackToTheStoredForm() {
        let english = Locale(identifier: "en_US")
        #expect(RecordAmountDisplay.ungrouped("1,234,567.89", locale: english) == "1234567.89")
        #expect(RecordAmountDisplay.ungrouped("1234.56", locale: english) == "1234.56")
        // A paste can carry the spaces other locales group with, whatever this locale uses.
        #expect(RecordAmountDisplay.ungrouped("1\u{202F}234\u{00A0}567", locale: english) == "1234567")
        #expect(RecordAmountDisplay.ungrouped("1.234.567,89", locale: Locale(identifier: "de_DE")) == "1234567,89")
    }

    /// What the field draws over itself as digits arrive. An empty field draws nothing, so its
    /// placeholder shows instead of a grouped "0", and every keystroke after that is grouped as it
    /// is typed rather than waiting for focus to move elsewhere.
    @Test func drawsGroupedDigitsFromTheFirstKeystrokeAndNothingWhileEmpty() {
        let locale = Locale(identifier: "en_US")
        #expect(RecordAmountDisplay.field("", locale: locale) == "")
        #expect(RecordAmountDisplay.field("1", locale: locale) == "1")
        #expect(RecordAmountDisplay.field("999", locale: locale) == "999")
        #expect(RecordAmountDisplay.field("1000", locale: locale) == "1,000")
        #expect(RecordAmountDisplay.field("1000.5", locale: locale) == "1,000.5")
        #expect(RecordAmountDisplay.field("-1000", locale: locale) == "-1,000")
    }

    /// What a field types into: every keystroke regroups for display and stores plain digits, so
    /// `AccountAmountInput.parse` keeps reading the same text it always did.
    @Test func roundTripsThroughAField() throws {
        let locale = Locale(identifier: "en_US")
        for typed in ["1", "12", "123", "1234", "1234567", "1234567.8"] {
            let displayed = RecordAmountDisplay.grouped(typed, locale: locale)
            let stored = RecordAmountDisplay.ungrouped(displayed, locale: locale)
            #expect(stored == typed)
            #expect(try AccountAmountInput.parse(stored, locale: locale) == Decimal(string: typed))
        }
    }
}
