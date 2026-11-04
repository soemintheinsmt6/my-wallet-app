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
                    .walletFirstRow(true)
            }
            ForEach(accounts) { account in
                Button {
                    selection = account.id
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: account.symbol)
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
                .walletFirstRow(account.id == accounts.first?.id)
            }
        }
        .listStyle(.plain)
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
            .walletFirstRow(type == PaymentType.allCases.first)
        }
        .listStyle(.plain)
        .navigationTitle("Payment type")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Text offered below a `RecordTextEntry` field, with an optional note such as its category.
struct TextEntrySuggestion: Hashable {
    let text: String
    var detail: String?
}

/// A pushed screen for one piece of text, focused on arrival so the keyboard is already up.
/// Edits go straight to the binding; Done or Back returns to the form.
struct RecordTextEntry: View {
    let title: String
    @Binding var text: String
    /// Shown small above the field, in place of a placeholder.
    let caption: String
    var multiline = false
    /// What to offer for the text typed so far; choosing one fills it in and returns to the form.
    var suggestions: ((String) -> [TextEntrySuggestion])?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        // No field chrome or placeholder: a small caption above, the text centred and large.
        ScrollView {
            VStack(spacing: WalletMetrics.small) {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Group {
                    if multiline {
                        TextField("", text: $text, axis: .vertical).lineLimit(1...12)
                    } else {
                        TextField("", text: $text).submitLabel(.done).onSubmit { dismiss() }
                    }
                }
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .focused($focused)
                .accessibilityLabel(caption)
                suggestionList
            }
            .padding(.horizontal, WalletMetrics.large)
            .padding(.top, 48)
        }
        .scrollDismissesKeyboard(.never)
        .navigationTitle(title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task {
            await Task.yield()
            focused = true
        }
    }

    /// Rows that fill the text in, so they carry no chevron: they return rather than open a screen.
    @ViewBuilder private var suggestionList: some View {
        let offered = suggestions?(text) ?? []
        if !offered.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(text.trimmingCharacters(in: .whitespaces).isEmpty ? "Recent" : "Suggestions")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, WalletMetrics.tight)
                ForEach(offered, id: \.self) { suggestion in
                    Button {
                        text = suggestion.text
                        dismiss()
                    } label: {
                        HStack(spacing: WalletMetrics.medium) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(suggestion.text).foregroundStyle(.primary).lineLimit(1)
                            Spacer(minLength: WalletMetrics.small)
                            if let detail = suggestion.detail {
                                Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(minHeight: WalletMetrics.touchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Uses this \(title.lowercased())")
                    if suggestion != offered.last { Divider() }
                }
            }
            .padding(.top, WalletMetrics.xxLarge)
        }
    }
}
