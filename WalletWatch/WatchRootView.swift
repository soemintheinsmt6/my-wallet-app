import SwiftUI
import WalletDomain

struct WatchRootView: View {
    @ObservedObject var store: WatchWalletStore

    var body: some View {
        TabView {
            WatchBalanceView(store: store)
            WatchTodayView(store: store)
            WatchQuickAddView(store: store)
        }
        .tabViewStyle(.verticalPage)
    }
}

/// Total balance, mirrored from the phone.
struct WatchBalanceView: View {
    @ObservedObject var store: WatchWalletStore

    private var balance: WalletSnapshot.Balance? { store.snapshot?.primaryBalance }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if let balance {
                    Text("Total Balance")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(balance.total.watchFormatted(balance.currencyCode))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(balance.total < 0 ? .red : .primary)
                    ForEach(others) { other in
                        HStack {
                            Text(other.currencyCode).font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text(other.total.watchFormatted(other.currencyCode))
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                } else {
                    WatchEmptyState(message: "Open My Wallet on your iPhone to sync.")
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Balance")
    }

    private var others: [WalletSnapshot.Balance] {
        (store.snapshot?.balances ?? []).filter { $0.currencyCode != balance?.currencyCode }
    }
}

/// Today's spending and this month's figures.
struct WatchTodayView: View {
    @ObservedObject var store: WatchWalletStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let month = store.snapshot?.month {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spent today").font(.caption2).foregroundStyle(.secondary)
                        Text((store.snapshot?.todaySpend ?? 0).watchFormatted(month.currencyCode))
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    Divider()
                    row("Income", month.income, month.currencyCode, .green)
                    row("Expenses", month.expenses, month.currencyCode, .red)
                    row("Net", month.net, month.currencyCode, month.net >= 0 ? .green : .red)
                } else {
                    WatchEmptyState(message: "No activity synced yet.")
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Today")
    }

    private func row(_ title: String, _ amount: Decimal, _ code: String, _ tint: Color) -> some View {
        HStack {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(amount.watchFormatted(code))
                .font(.caption)
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }
}

struct WatchEmptyState: View {
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone.and.arrow.forward")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }
}

extension Decimal {
    /// Compact money for the small screen; the phone keeps the full precision.
    func watchFormatted(_ currencyCode: String) -> String {
        formatted(.currency(code: currencyCode).precision(.fractionLength(0...2)))
    }
}
