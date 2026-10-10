import SwiftUI
import WalletDomain

/// Home-currency settings: pick the currency, opt into converted totals, and refresh rates.
struct CurrencySettingsSection: View {
    @ObservedObject var viewModel: CurrencyViewModel
    @State private var isChoosingCurrency = false

    var body: some View {
        Section {
            Button { isChoosingCurrency = true } label: {
                LabeledContent("Home Currency", value: viewModel.homeCurrency)
            }
            .foregroundStyle(.primary)

            NavigationLink {
                CurrencyPickerView(selection: $viewModel.defaultCurrency, pushed: true)
            } label: {
                LabeledContent("Default Currency", value: viewModel.defaultCurrency)
            }

            Toggle("Show Converted Totals", isOn: $viewModel.convertsTotals)

            if viewModel.convertsTotals {
                if viewModel.isRefreshing {
                    HStack {
                        ProgressView()
                        Text("Updating rates…").foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        Task { await viewModel.refresh(force: true) }
                    } label: {
                        Label("Update Rates Now", systemImage: "arrow.clockwise")
                    }
                }
                if let updated = viewModel.lastUpdated {
                    LabeledContent("Rates Updated",
                                   value: updated.formatted(date: .abbreviated, time: .shortened))
                }
                if let message = viewModel.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Currency")
        } footer: {
            Text("New accounts, bills, budgets, debts and goals start in the default currency. Accounts keep their own currency. Converted totals are estimates from daily reference rates and never replace the per-currency figures. Rates download from the European Central Bank's public feed.")
        }
        .sheet(isPresented: $isChoosingCurrency) {
            CurrencyPickerView(selection: $viewModel.homeCurrency)
        }
    }
}

/// A converted figure, always marked as an estimate so it is never mistaken for a booked amount.
struct ConvertedAmountText: View {
    let amount: Decimal
    let currencyCode: String
    var font: Font = .caption

    var body: some View {
        Text("≈ \(amount.walletFormatted(currencyCode))")
            .font(font)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityLabel("Approximately \(amount.walletFormatted(currencyCode))")
    }
}
