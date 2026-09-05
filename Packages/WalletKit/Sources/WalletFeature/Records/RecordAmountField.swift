import SwiftUI
import WalletDomain

struct RecordAmountField<Field: Hashable>: View {
    let kind: RecordKind
    let currency: String
    @Binding var amount: String
    let focus: FocusState<Field?>.Binding
    let field: Field
    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize = 60

    private var amountColor: Color {
        kind == .expense ? .red : kind == .income ? .green : .primary
    }

    var body: some View {
        HStack(spacing: 16) {
            if !currency.isEmpty {
                Text(currency)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.4), in: Capsule())
                    .accessibilityLabel("Currency \(currency)")
            }
            ZStack(alignment: .trailing) {
                // The overlay keeps the sign next to the digits without storing it in the input.
                Text("\(kind == .expense ? "−" : kind == .income ? "+" : "")\(RecordAmountDisplay.grouped(amount))")
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .accessibilityHidden(true)
                TextField("", text: $amount)
                    .focused(focus, equals: field)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .accessibilityLabel("\(kind.title) amount")
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
            }
            .font(.system(size: amountFontSize, weight: .regular))
            .monospacedDigit()
            .foregroundStyle(amountColor)
            .frame(maxWidth: .infinity, minHeight: 76)
        }
        .padding(.vertical, 4)

    }
}
