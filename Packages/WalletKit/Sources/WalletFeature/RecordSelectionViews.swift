import SwiftUI
import WalletDomain

struct RecordAccountSelection: View {
    let accounts: [Account]
    @Binding var selection: UUID?
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if accounts.isEmpty {
                Text("No available accounts. Create an account in the Accounts tab.")
                    .foregroundStyle(.secondary)
            }
            ForEach(accounts) { account in
                Button {
                    selection = account.id
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: account.type.symbol)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(account.settings.color.tint, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(account.name).foregroundStyle(.primary)
                            Text(account.currencyCode).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selection == account.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == account.id ? .isSelected : [])
            }
        }
        .navigationTitle(title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct RecordPaymentSelection: View {
    @Binding var selection: PaymentType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(PaymentType.allCases) { type in
            Button {
                selection = type
                dismiss()
            } label: {
                HStack {
                    Text(type.title).foregroundStyle(.primary)
                    Spacer()
                    if selection == type { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection == type ? .isSelected : [])
        }
        .navigationTitle("Payment type")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
