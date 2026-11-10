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

    /// Accounts keep a stable, meaningful order: by type, then by name within a type. The type is
    /// shown on each row rather than as a section, since most types hold only one or two accounts.
    private var sortedAccounts: [Account] {
        AccountType.allCases.flatMap { type in
            viewModel.accounts.filter { $0.type == type }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    public var body: some View {
        List {
            if !viewModel.accounts.isEmpty { totalsSection }
            alertsSection
            Section {
                ForEach(sortedAccounts) { account in row(account) }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.accounts.isEmpty {
                if viewModel.isLoading {
                    WalletLoadingState(message: "Loading accounts…")
                } else {
                    WalletEmptyState(title: "Your wallet starts here", symbol: WalletSymbols.wallet,
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

    /// A header above the list rather than a row in it: no separators, and the explanation as a
    /// caption, since a flat list would otherwise draw its footer as a full-size row of text.
    private var totalsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: WalletMetrics.medium) {
                ForEach(totals, id: \.currency) { total in
                    VStack(alignment: .leading, spacing: WalletMetrics.tight) {
                        Text(totals.count > 1 ? "Total · \(total.currency)" : "Total balance")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(total.amount.walletFormatted(total.currency))
                            // One total leads the screen; several share it at a smaller size.
                            .font(.system(totals.count > 1 ? .title : .largeTitle, design: .rounded,
                                          weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(total.amount < 0 ? .red : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Accounts included in statistics. Currencies are never combined.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, WalletMetrics.small)
            .listRowSeparator(.hidden)
        }
        .listSectionSeparator(.hidden)
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
                WalletIconTile(symbol: account.symbol, color: account.settings.color.tint, large: true)
                VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                    Text(account.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if account.settings.excludeFromStats {
                        Label(subtitle(["Excluded from stats", account.maskedAccountNumber]) ?? "",
                              systemImage: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let line = subtitle([typeLine(account), account.maskedAccountNumber]) {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                // Every row's separator starts under the name. Without this, the "Excluded from
                // stats" Label pulls it in to its own text, past the eye icon.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
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

    /// The balance already carries the currency, so the type says more here. Skipped when it would
    /// only repeat the name, as with "Cash".
    private func typeLine(_ account: Account) -> String? {
        account.name.caseInsensitiveCompare(account.type.title) == .orderedSame ? nil : account.type.title
    }

    /// Joins the parts that are present with " · ", or `nil` when none are.
    private func subtitle(_ parts: [String?]) -> String? {
        let present = parts.compactMap { $0 }
        return present.isEmpty ? nil : present.joined(separator: " · ")
    }
}
