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
    /// Pair it with `groupedAmountOverlay(_:)`, which is what actually puts the separators on
    /// screen while the field is being typed into. This side keeps the state plain and takes the
    /// separators back out of a pasted number.
    func groupedAmount(locale: Locale = .current) -> Binding<String> {
        Binding<String>(
            get: { RecordAmountDisplay.field(self.wrappedValue, locale: locale) },
            set: { self.wrappedValue = RecordAmountDisplay.ungrouped($0, locale: locale) }
        )
    }
}

extension View {
    /// Draws an amount field's digits grouped, over the field itself.
    ///
    /// The binding above cannot do this alone: a field holding focus keeps the text the person
    /// typed and ignores the grouped value handed back to it, so the separators only appeared once
    /// something else took focus — editing the account name, say. The typed digits are hidden and
    /// the grouped ones drawn on top instead, so a separator arrives on the keystroke that earns
    /// it. It is how the large record amount field has always worked.
    ///
    /// The field underneath still holds the text, so selection, the caret and the keyboard are the
    /// field's own. Trailing alignment — what an amount field wants anyway — keeps the caret with
    /// the last digit, since both the typed text and the drawn text end at the same edge.
    func groupedAmountOverlay(_ amount: String, alignment: Alignment = .trailing,
                              locale: Locale = .current) -> some View {
        // Hidden only once there is something to hide, so an empty field still draws its placeholder.
        foregroundStyle(amount.isEmpty ? Color.primary : Color.clear)
            .overlay(alignment: alignment) {
                Text(RecordAmountDisplay.field(amount, locale: locale))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    // The field keeps the taps and the accessibility element; this is only paint.
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}
