import SwiftUI
import WalletDomain

public struct AccountsView: View {
    @ObservedObject private var viewModel: AccountsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isCreatingAccount = false
    @State private var editingAccount: Account?
    @State private var deletingAccount: Account?

    public init(viewModel: AccountsViewModel) { self.viewModel = viewModel }

    /// Totals never combine currencies, so the header shows one line per currency in use.
    private var totals: [(currency: String, amount: Decimal)] {
        let included = viewModel.accountsIncludedInStats
        return Dictionary(grouping: included, by: \.currencyCode)
            .map { (currency: $0.key, amount: $0.value.reduce(0) { $0 + $1.settings.currentBalance }) }
            .sorted { $0.currency < $1.currency }
    }

    /// Accounts keep a stable, meaningful order: by type, then by name within a type.
    private var groups: [(type: AccountType, accounts: [Account])] {
        AccountType.allCases.compactMap { type in
            let matching = viewModel.accounts.filter { $0.type == type }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return matching.isEmpty ? nil : (type, matching)
        }
    }

    public var body: some View {
        List {
            if !viewModel.accounts.isEmpty { totalsSection }
            alertsSection
            ForEach(groups, id: \.type) { group in
                Section(group.type.title) {
                    ForEach(group.accounts) { account in row(account) }
                }
            }
        }
        .overlay {
            if viewModel.accounts.isEmpty {
                if viewModel.isLoading {
                    WalletLoadingState(message: "Loading accounts…")
                } else {
                    WalletEmptyState(title: "Your wallet starts here", symbol: "wallet.bifold",
                                     message: "Create your first account to organize your money.",
                                     actionTitle: "Create Account") { isCreatingAccount = true }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem {
                Button { isCreatingAccount = true } label: {
                    Label("Create Account", systemImage: "plus")
                }
            }
        }
        .refreshable { await viewModel.reload() }
        .sheet(isPresented: $isCreatingAccount) { AccountEditorView(viewModel: viewModel) }
        .sheet(item: $deletingAccount) { AccountDeletionView(viewModel: viewModel, account: $0) }
        .sheet(item: $editingAccount) { AccountEditorView(viewModel: viewModel, account: $0) }
        .alert("Unable to Load Accounts", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("Retry") { Task { await viewModel.reload() } }
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
        .task { await viewModel.observe() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.reload() } }
        }
    }

    private var totalsSection: some View {
        Section {
            ForEach(totals, id: \.currency) { total in
                VStack(alignment: .leading, spacing: WalletMetrics.tight) {
                    Text(totals.count > 1 ? "Total · \(total.currency)" : "Total balance")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(total.amount.walletFormatted(total.currency))
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(total.amount < 0 ? .red : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(.vertical, WalletMetrics.tight)
                .accessibilityElement(children: .combine)
            }
        } footer: {
            Text("Totals cover accounts included in statistics and stay separate per currency.")
        }
    }

    @ViewBuilder private var alertsSection: some View {
        if !viewModel.balanceNotifications.isEmpty {
            Section("Balance alerts") {
                ForEach(viewModel.balanceNotifications) { account in
                    Button { editingAccount = account } label: {
                        HStack(spacing: WalletMetrics.medium) {
                            WalletIconTile(symbol: "bell.badge", color: .red)
                            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                                Text(account.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(account.settings.isBelowMinimum ? "Balance below minimum" : "Balance above maximum")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                Text("Limit: \((account.settings.isBelowMinimum ? account.settings.minimumBalance : account.settings.maximumBalance).walletFormatted(account.currencyCode))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: WalletMetrics.small)
                            WalletDisclosure()
                        }
                        .frame(minHeight: WalletMetrics.touchTarget)
                        .padding(.vertical, WalletMetrics.tight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit account")
                }
            }
        }
    }

    private func row(_ account: Account) -> some View {
        Button { editingAccount = account } label: {
            HStack(spacing: WalletMetrics.medium) {
                WalletIconTile(symbol: account.type.symbol, color: account.settings.color.tint, large: true)
                VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                    Text(account.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if account.settings.excludeFromStats {
                        Label("Excluded from stats", systemImage: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(account.currencyCode)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: WalletMetrics.small)
                Text(account.settings.currentBalance.walletFormatted(account.currencyCode))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(account.settings.currentBalance < 0 ? .red : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                WalletDisclosure()
            }
            .frame(minHeight: WalletMetrics.touchTarget)
            .padding(.vertical, WalletMetrics.tight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit account")
        .swipeActions {
            Button("Delete", role: .destructive) { deletingAccount = account }
        }
        .contextMenu {
            Button("Delete Account", role: .destructive) { deletingAccount = account }
        }
    }
}
