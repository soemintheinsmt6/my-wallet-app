import SwiftUI
import WalletDomain

/// Currency settings: pick the main currency, choose how large amounts count, opt into converted
/// totals, and refresh rates.
struct CurrencySettingsSection: View {
    @ObservedObject var viewModel: CurrencyViewModel
    @AppStorage(WalletPreferenceKeys.numberScale) private var numberScale = NumberScale.automatic.rawValue

    var body: some View {
        Section {
            NavigationLink {
                CurrencyPickerView(selection: $viewModel.mainCurrency, pushed: true)
            } label: {
                LabeledContent("Main Currency", value: viewModel.mainCurrency)
            }

            WalletMenuPicker("Count Large Amounts In", selection: $numberScale,
                             value: (NumberScale(rawValue: numberScale) ?? .automatic).title) {
                ForEach(NumberScale.allCases) { scale in
                    Text(scale.title).tag(scale.rawValue)
                }
            }

            Toggle("Show Converted Totals", isOn: $viewModel.convertsTotals)

            if viewModel.convertsTotals && !viewModel.hasRatesForMainCurrency {
                Label("Automatic rates aren't published for \(viewModel.mainCurrency), so totals stay separate per currency. A record can still convert with a rate you enter in it.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if viewModel.convertsTotals {
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
            Text("New accounts, bills, budgets, debts and goals start in the main currency, summaries open in it, and converted totals are shown in it. Accounts keep their own currency. Chart totals count large amounts in lakhs (52.7 lakhs) or millions (5.3M); Automatic uses lakhs for MMK, INR, PKR, BDT, NPR and LKR. Converted totals are estimates from daily reference rates and never replace the per-currency figures. Rates download from the European Central Bank's public feed.")
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
