import SwiftUI
import WalletDomain

/// The large amount entry at the top of an editor, with its currency as a chip beside it.
struct RecordAmountField<Field: Hashable>: View {
    let sign: String
    let color: Color
    let label: String
    let currency: String
    @Binding var amount: String
    let focus: FocusState<Field?>.Binding
    let field: Field
    /// When set, the currency chip is a button that lets the person choose another currency.
    var chooseCurrency: (() -> Void)?
    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize = 60

    /// A record's amount: red with a minus for spending, green with a plus for income.
    init(kind: RecordKind, currency: String, amount: Binding<String>,
         focus: FocusState<Field?>.Binding, field: Field) {
        self.init(sign: kind == .expense ? "−" : kind == .income ? "+" : "",
                  color: kind == .expense ? .red : kind == .income ? .green : .primary,
                  label: "\(kind.title) amount", currency: currency, amount: amount, focus: focus, field: field)
    }

    init(sign: String, color: Color, label: String, currency: String, amount: Binding<String>,
         focus: FocusState<Field?>.Binding, field: Field, chooseCurrency: (() -> Void)? = nil) {
        self.sign = sign
        self.color = color
        self.label = label
        self.currency = currency
        _amount = amount
        self.focus = focus
        self.field = field
        self.chooseCurrency = chooseCurrency
    }

    var body: some View {
        HStack(spacing: 16) {
            if !currency.isEmpty {
                if let chooseCurrency {
                    // The record editor's chip with its text in the accent color, as tappable text
                    // is in iOS, so it reads as a button without a chevron.
                    Button(action: chooseCurrency) {
                        Text(currency).currencyChip(color: .accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Currency \(currency)")
                    .accessibilityHint("Choose another currency")
                } else {
                    Text(currency)
                        .currencyChip()
                        .accessibilityLabel("Currency \(currency)")
                }
            }
            ZStack(alignment: .trailing) {
                // The overlay keeps the sign next to the digits without storing it in the input.
                Text("\(sign)\(RecordAmountDisplay.grouped(amount))")
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .accessibilityHidden(true)
                TextField("", text: $amount)
                    .focused(focus, equals: field)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .accessibilityLabel(label)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
            }
            .font(.system(size: amountFontSize, weight: .regular))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 76)
        }
        .padding(.vertical, 4)

    }
}

private extension View {
    func currencyChip(color: Color = .primary) -> some View {
        font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.4), in: Capsule())
            .contentShape(Capsule())
    }
}
