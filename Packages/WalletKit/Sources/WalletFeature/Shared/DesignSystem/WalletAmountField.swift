import SwiftUI

/// An amount field that shows the locale's digit grouping as the digits are typed.
///
/// The digits on screen are drawn by a `Text`, with the real field laid over them clear. It has to
/// be this way round. A field that is first responder keeps the text typed into it and ignores what
/// is pushed back at it — both a regrouped value and a "hide your own text now" colour — so nothing
/// landed until focus moved elsewhere, and until it did the plain digits and the grouped ones were
/// drawn one over the other. Painting the digits ourselves keeps them a keystroke fresh, and the
/// field's own colour is set clear once, at the start, where it is never a change to be ignored.
///
/// The field underneath still holds the text, the caret and the keyboard. Both layers end at the
/// same edge, so with the trailing alignment an amount field wants anyway the caret stays with the
/// last digit.
///
/// Type comes from the environment, so set `font` and `monospacedDigit` on the whole field rather
/// than on the `TextField` inside it: a modifier applied in there reaches only the layer it is
/// applied to, and the two would be drawn in different type.
struct WalletAmountField<Field: View>: View {
    /// The plain digits the field holds; what the drawn text is grouped from.
    let amount: String
    var placeholder: String = "0"
    var alignment: TextAlignment = .trailing
    var locale: Locale = .current
    /// The real field, so the screen that owns it keeps its focus, keyboard and accessibility.
    @ViewBuilder let field: Field

    private var frameAlignment: Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var body: some View {
        ZStack(alignment: frameAlignment) {
            Text(amount.isEmpty ? placeholder : RecordAmountDisplay.grouped(amount, locale: locale))
                // The field's own placeholder would be hidden along with its text, so it is drawn
                // here instead, in the colour a placeholder is expected to have.
                .foregroundStyle(amount.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                // The field keeps the taps and the accessibility element; this is only paint.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            field
                .foregroundStyle(Color.clear)
                .multilineTextAlignment(alignment)
        }
    }
}
