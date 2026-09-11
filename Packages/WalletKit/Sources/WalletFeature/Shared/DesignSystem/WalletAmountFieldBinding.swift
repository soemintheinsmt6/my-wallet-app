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
    /// Regrouping on every keystroke puts the caret back at the end of the field. That is where
    /// digits are appended anyway, and it is what the large record amount field already does.
    func groupedAmount(locale: Locale = .current) -> Binding<String> {
        Binding<String>(
            // An empty field stays empty so its placeholder shows, rather than grouping to "0".
            get: { self.wrappedValue.isEmpty ? "" : RecordAmountDisplay.grouped(self.wrappedValue, locale: locale) },
            set: { self.wrappedValue = RecordAmountDisplay.ungrouped($0, locale: locale) }
        )
    }
}
