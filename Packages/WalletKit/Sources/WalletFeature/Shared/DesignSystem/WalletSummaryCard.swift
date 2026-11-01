import SwiftUI
import WalletDomain

/// A period's income, expenses and net as one card: net leads, a bar shows how the two compare,
/// and the totals sit underneath. Fills a single ordinary list row so the section keeps its shape.
struct WalletSummaryCard: View {
    /// Spending set against the previous period, as a relative change.
    struct Comparison {
        /// What it is compared with, such as "vs last month".
        let label: String
        /// `nil` when the previous period had no spending to compare with.
        let change: Double?
    }

    let income: Decimal
    let expenses: Decimal
    let currencyCode: String
    /// Optional detail shown under the totals; the dashboard leaves both out.
    var dailyAverage: Decimal?
    var comparison: Comparison?

    private var net: Decimal { income - expenses }

    var body: some View {
        VStack(alignment: .leading, spacing: WalletMetrics.large) {
            VStack(alignment: .leading, spacing: WalletMetrics.tight) {
                Text("Net")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                WalletAmountText.net(net, currencyCode: currencyCode, font: .largeTitle.weight(.bold))
                Text(context)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            ratioBar

            HStack(alignment: .top, spacing: WalletMetrics.medium) {
                total("Income", amount: income, symbol: "arrow.down.left", tint: .green)
                Divider()
                total("Expenses", amount: expenses, symbol: "arrow.up.right", tint: .red)
            }
            .fixedSize(horizontal: false, vertical: true)

            if dailyAverage != nil || comparison != nil {
                Divider()
                HStack(alignment: .top, spacing: WalletMetrics.medium) {
                    if let dailyAverage {
                        detail("Spent per day") {
                            Text(dailyAverage.walletFormatted(currencyCode))
                        }
                    }
                    if let comparison {
                        Divider()
                        detail(comparison.label) { changeText(comparison.change) }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, WalletMetrics.small)
        // The list would start the row's separator at a label inside the card; start it at the
        // card's edge like every other row.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }

    private func detail(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: WalletMetrics.tight) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            value()
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Spending up reads red and down green; the arrow and the words carry it without color too.
    @ViewBuilder private func changeText(_ change: Double?) -> some View {
        if let change {
            let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
            if abs(change) < 0.005 {
                Label("About the same", systemImage: "equal")
                    .foregroundStyle(.secondary)
            } else if change > 0 {
                Label("\(percent) more", systemImage: "arrow.up.right").foregroundStyle(.red)
            } else {
                Label("\(percent) less", systemImage: "arrow.down.right").foregroundStyle(.green)
            }
        } else {
            Text("No spending then").foregroundStyle(.secondary)
        }
    }

    /// What the net means in a sentence, so a large red number is not the only cue.
    private var context: String {
        if income == 0 && expenses == 0 { return "No income or expenses yet." }
        if income == 0 { return "No income recorded this period." }
        let share = NSDecimalNumber(decimal: expenses / income).doubleValue
        return "Spent \(share.formatted(.percent.precision(.fractionLength(0)))) of income"
    }

    /// Income against expenses as one split bar; a neutral track when there is nothing to compare.
    private var ratioBar: some View {
        GeometryReader { proxy in
            let total = NSDecimalNumber(decimal: income + expenses).doubleValue
            let incomeShare = total > 0 ? NSDecimalNumber(decimal: income).doubleValue / total : 0
            HStack(spacing: total > 0 && incomeShare > 0 && incomeShare < 1 ? WalletMetrics.hair : 0) {
                if total == 0 {
                    Capsule().fill(.quaternary)
                } else {
                    if incomeShare > 0 { Capsule().fill(Color.green.gradient).frame(width: proxy.size.width * incomeShare) }
                    if incomeShare < 1 { Capsule().fill(Color.red.gradient) }
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private func total(_ title: String, amount: Decimal, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: WalletMetrics.tight) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 18, height: 18)
                    .background(tint.opacity(0.15), in: Circle())
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            Text(amount.walletFormatted(currencyCode))
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        Section("This Month") {
            WalletSummaryCard(income: 2_000_000, expenses: 5_270_000, currencyCode: "MMK")
        }
        Section("With detail") {
            WalletSummaryCard(income: 2_000_000, expenses: 1_270_000, currencyCode: "MMK",
                              dailyAverage: 42_333, comparison: .init(label: "vs last month", change: -0.12))
        }
        Section("Empty") {
            WalletSummaryCard(income: 0, expenses: 0, currencyCode: "MMK")
        }
    }
}
