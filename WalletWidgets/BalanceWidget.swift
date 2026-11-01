import SwiftUI
import WalletDomain
import WidgetKit

/// Total balance across accounts included in statistics, kept separate per currency.
struct BalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WalletBalanceWidget", provider: WalletProvider()) { entry in
            BalanceWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Total Balance")
        .description("Your total balance across accounts included in statistics.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BalanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WalletEntry

    private var balances: [WalletSnapshot.Balance] { entry.snapshot?.balances ?? [] }
    private var primary: WalletSnapshot.Balance? { entry.snapshot?.primaryBalance }
    /// Other currencies, most accounts first, shown only where there is room.
    private var others: [WalletSnapshot.Balance] {
        balances.filter { $0.currencyCode != primary?.currencyCode }
            .sorted { $0.accountCount > $1.accountCount }
    }

    var body: some View {
        Group {
            if let primary {
                content(primary)
            } else {
                WidgetEmptyState(message: "Create an account to see your balance.")
            }
        }
        .widgetURL(WalletDeepLink.home.url)
    }

    private func content(_ primary: WalletSnapshot.Balance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Total Balance", systemImage: WalletSymbols.wallet)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            Text(family == .systemSmall
                 ? primary.total.widgetCompact(primary.currencyCode)
                 : primary.total.widgetFormatted(primary.currencyCode))
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(primary.total < 0 ? .red : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(primary.accountCount == 1 ? "1 account" : "\(primary.accountCount) accounts")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !others.isEmpty {
                Spacer(minLength: 2)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(others.prefix(family == .systemSmall ? 1 : 3)) { balance in
                        HStack(spacing: 4) {
                            Text(balance.currencyCode)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 2)
                            Text(balance.total.widgetCompact(balance.currencyCode))
                                .font(.caption2)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
