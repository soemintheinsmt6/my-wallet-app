import SwiftUI
import WalletDomain

/// How this month's bills stand: "3 of 5 paid" over a bar, and the amounts when every bill due is in
/// one currency. The bar fills and the figures roll up when the screen reveals its charts (see
/// `walletChartsRevealed`), and move together when a bill is marked paid. Decorative bar: the text
/// says the same.
struct BillMonthProgressView: View {
    let progress: BillPeriodProgress
    @Environment(\.walletChartsRevealed) private var revealed

    var body: some View {
        let paid = revealed ? progress.paidCount : 0
        let done = progress.paidCount == progress.dueCount
        let tint: Color = done ? .green : .accentColor
        VStack(alignment: .leading, spacing: WalletMetrics.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("This month")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: WalletMetrics.small)
                Text(done ? "All \(progress.dueCount) paid" : "\(paid) of \(progress.dueCount) paid")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(done ? Color.green : Color.primary)
                    .contentTransition(.numericText(value: Double(paid)))
            }
            WalletProgressBar(value: progress.fraction, tint: tint, height: 8)
            if let code = progress.currencyCode, let due = progress.dueAmount, let paidAmount = progress.paidAmount {
                let shown = revealed ? paidAmount : 0
                Text("\(shown.walletFormatted(code)) of \(due.walletFormatted(code))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText(value: shown.doubleValue))
            }
        }
        // Marking a bill paid moves the count and amount with the bar, which animates on its own.
        .animation(.easeOut(duration: 0.3), value: progress)
        .accessibilityElement(children: .combine)
    }
}

extension BillPeriodProgress {
    /// This calendar month's bills, for the Bills screen and the Dashboard.
    static func thisMonth(_ bills: [BillReminder], now: Date = Date()) -> BillPeriodProgress? {
        guard let month = Calendar.current.dateInterval(of: .month, for: now) else { return nil }
        let progress = BillPeriodProgress(bills: bills, in: month)
        return progress.dueCount > 0 ? progress : nil
    }
}
