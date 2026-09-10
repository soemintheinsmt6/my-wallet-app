import SwiftUI
import WalletDomain
import WidgetKit

/// This month's income, expenses and net for the leading currency.
struct MonthlySpendingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WalletMonthlySpendingWidget", provider: WalletProvider()) { entry in
            MonthlySpendingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("This Month")
        .description("Income, expenses and net for the current month.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MonthlySpendingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WalletEntry

    private var month: WalletSnapshot.Month? { entry.snapshot?.month }

    var body: some View {
        Group {
            if let month {
                content(month)
            } else {
                WidgetEmptyState(message: "No activity to summarize yet.")
            }
        }
        .widgetURL(WalletDeepLink.statistics.url)
    }

    private func content(_ month: WalletSnapshot.Month) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(month.start.formatted(.dateTime.month(.wide)))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if family == .systemSmall {
                figure("Spent", month.expenses, month.currencyCode, .red, compact: true)
                figure("Income", month.income, month.currencyCode, .green, compact: true)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    figure("Income", month.income, month.currencyCode, .green, compact: false)
                    figure("Expenses", month.expenses, month.currencyCode, .red, compact: false)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text("Net")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(netText(month))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(month.net > 0 ? .green : month.net < 0 ? .red : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The sign comes from the value, never from a stored negative amount.
    private func netText(_ month: WalletSnapshot.Month) -> String {
        let magnitude = abs(month.net)
        let prefix = month.net > 0 ? "+" : month.net < 0 ? "−" : ""
        return prefix + (family == .systemSmall
                         ? magnitude.widgetCompact(month.currencyCode)
                         : magnitude.widgetFormatted(month.currencyCode))
    }

    private func figure(_ title: String, _ amount: Decimal, _ currency: String,
                        _ tint: Color, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(compact ? amount.widgetCompact(currency) : amount.widgetFormatted(currency))
                .font(compact ? .callout.weight(.semibold) : .title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
