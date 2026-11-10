import SwiftUI
import WalletDomain

struct BudgetProgressRow: View {
    let progress: BudgetProgress

    /// Color reinforces the status text but never carries it alone — `progress.status` is always shown.
    private var tint: Color {
        if progress.ratio >= 1 { return .red }
        return progress.ratio >= 0.8 ? .orange : .green
    }

    private var fraction: Double { min(1, max(0, progress.ratio)) }

    var body: some View {
        VStack(alignment: .leading, spacing: WalletMetrics.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.budget.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: WalletMetrics.small)
                Text(progress.status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
            }

            BudgetBar(fraction: fraction, tint: tint)

            HStack(alignment: .firstTextBaseline) {
                Text("\(money(progress.spent)) of \(money(progress.limit))")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: WalletMetrics.small)
                Text(progress.remaining >= 0 ? "\(money(progress.remaining)) left" : "\(money(-progress.remaining)) over")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(progress.remaining >= 0 ? Color.primary : Color.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if progress.carried > 0 {
                Text("Includes \(money(progress.carried)) rolled over")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, WalletMetrics.small)
        .accessibilityElement(children: .combine)
    }

    private func money(_ amount: Decimal) -> String { amount.walletFormatted(progress.budget.currencyCode) }
}

/// A capsule meter. Decorative: the row states spent, limit, remaining and status in text.
private struct BudgetBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
        .frame(height: WalletMetrics.small)
        .animation(.default, value: fraction)
        .accessibilityHidden(true)
    }
}

struct BudgetProgressSection: View {
    @ObservedObject var viewModel: PlanningViewModel
    var categoryID: UUID?
    /// The editors' band heading, for flat detail screens; otherwise the list's own header.
    var bandHeader = false

    var body: some View {
        let values = viewModel.progress(categoryID: categoryID)
        if !values.isEmpty {
            Section {
                ForEach(values) { BudgetProgressRow(progress: $0) }
            } header: {
                if bandHeader { WalletListSectionHeader("Budget progress") } else { Text("Budget progress") }
            }
        }
    }
}
