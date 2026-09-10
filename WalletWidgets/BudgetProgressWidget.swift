import SwiftUI
import WalletDomain
import WidgetKit

/// Budget progress, tightest budget first.
struct BudgetProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WalletBudgetProgressWidget", provider: WalletProvider()) { entry in
            BudgetProgressWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Budget Progress")
        .description("How your budgets are tracking this period.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct BudgetProgressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WalletEntry

    private var limit: Int {
        switch family {
        case .systemSmall: 1
        case .systemLarge: 4
        default: 2
        }
    }

    private var budgets: [WalletSnapshot.BudgetProgressSummary] {
        Array((entry.snapshot?.budgets ?? []).prefix(limit))
    }

    var body: some View {
        Group {
            if budgets.isEmpty {
                WidgetEmptyState(message: "Create a budget to track spending limits.")
            } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 10) {
                    Text("Budgets")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(budgets) { budget in
                        row(budget)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .widgetURL(WalletDeepLink.planning.url)
    }

    /// Color supports the status text; it never carries the meaning alone.
    private func tint(_ budget: WalletSnapshot.BudgetProgressSummary) -> Color {
        if budget.isOverBudget { return .red }
        return budget.fraction >= 0.8 ? .orange : .green
    }

    private func row(_ budget: WalletSnapshot.BudgetProgressSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(budget.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(budget.status)
                    .font(.caption2)
                    .foregroundStyle(tint(budget))
                    .lineLimit(1)
            }
            ProgressView(value: budget.fraction)
                .tint(tint(budget))
                .scaleEffect(x: 1, y: family == .systemSmall ? 1 : 1.2, anchor: .center)
            Text("\(budget.spent.widgetFormatted(budget.currencyCode)) of \(budget.limit.widgetFormatted(budget.currencyCode))")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
