import SwiftUI
import WalletDomain

struct BudgetProgressRow: View {
    let progress: BudgetProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(progress.budget.name).font(.headline)
                Spacer()
                Text(progress.status).font(.caption).foregroundStyle(progress.ratio >= 1 ? .red : .secondary)
            }
            ProgressView(value: min(1, max(0, progress.ratio))).tint(progress.ratio >= 1 ? .red : .accentColor)
            Text("\(money(progress.spent)) spent / \(money(progress.limit)) available")
                .font(.subheadline).monospacedDigit()
            if progress.carried > 0 { Text("Includes \(money(progress.carried)) rolled over").font(.caption).foregroundStyle(.secondary) }
            Text(progress.remaining >= 0 ? "\(money(progress.remaining)) remaining" : "\(money(-progress.remaining)) over budget")
                .font(.caption)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
    private func money(_ amount: Decimal) -> String { amount.formatted(.currency(code: progress.budget.currencyCode)) }
}

struct BudgetProgressSection: View {
    @ObservedObject var viewModel: PlanningViewModel
    var categoryID: UUID?
    var body: some View {
        let values = viewModel.progress(categoryID: categoryID)
        if !values.isEmpty {
            Section("Budget progress") { ForEach(values) { BudgetProgressRow(progress: $0) } }
        }
    }
}
