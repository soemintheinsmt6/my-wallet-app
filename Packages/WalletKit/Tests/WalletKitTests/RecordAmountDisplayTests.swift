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
}
