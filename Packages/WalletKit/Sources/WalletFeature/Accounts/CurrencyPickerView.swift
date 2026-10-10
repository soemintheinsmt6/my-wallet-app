import SwiftUI

struct CurrencyPickerView: View {
    @Binding var selection: String
    /// Pushed inside an existing navigation stack instead of presented as its own sheet.
    var pushed = false
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var currencies: [String] {
        Locale.commonISOCurrencyCodes.sorted().filter {
            search.isEmpty || $0.localizedCaseInsensitiveContains(search) ||
                (Locale.current.localizedString(forCurrencyCode: $0) ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        if pushed {
            list
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        } else {
            NavigationStack {
                list.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
            #endif
        }
    }

    private var list: some View {
        List(currencies, id: \.self) { code in
            Button {
                selection = code
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(code).font(.headline)
                        Text(Locale.current.localizedString(forCurrencyCode: code) ?? code)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if code == selection { Image(systemName: "checkmark") }
                }
                .foregroundStyle(.primary)
            }
            .accessibilityAddTraits(code == selection ? .isSelected : [])
        }
        .searchable(text: $search, prompt: "Currency name or code")
        .navigationTitle("Currency")
    }
}
