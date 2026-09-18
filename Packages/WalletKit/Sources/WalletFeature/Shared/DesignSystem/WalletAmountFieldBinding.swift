import SwiftUI

extension Binding where Value == String {
    /// Shows an amount field with the locale's digit grouping while the bound state keeps the plain
    /// digits `AccountAmountInput.parse` expects.
    ///
    /// Grouping is added on the way to the field and stripped on the way back, so typing, pasting a
    /// grouped number and seeding from `AccountAmountInput.text` all settle into the same plain
    /// form. Nothing else in a screen has to change: validation, drafts and saving keep reading the
    /// same state they always did.
    ///
    /// `WalletAmountField` is what puts the separators on screen while the field is being typed
    /// into. This side keeps the state plain and takes the separators back out of a pasted number.
    func groupedAmount(locale: Locale = .current) -> Binding<String> {
        Binding<String>(
            get: { RecordAmountDisplay.field(self.wrappedValue, locale: locale) },
            set: { self.wrappedValue = RecordAmountDisplay.ungrouped($0, locale: locale) }
        )
    }
}

