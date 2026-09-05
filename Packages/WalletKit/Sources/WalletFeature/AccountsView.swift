import SwiftUI
import WalletDomain

public struct AccountsView: View {
    @ObservedObject private var viewModel: AccountsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isCreatingAccount = false
    @State private var editingAccount: Account?

    public init(viewModel: AccountsViewModel) { self.viewModel = viewModel }

    public var body: some View {
        NavigationStack {
            List {
                if !viewModel.balanceNotifications.isEmpty {
                    Section("In-app notifications") {
                        ForEach(viewModel.balanceNotifications) { account in
                            Button { editingAccount = account } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(account.name).font(.headline)
                                        Text(account.settings.isBelowMinimum ? "Balance below minimum" : "Balance above maximum")
                                        Text("Limit: \((account.settings.isBelowMinimum ? account.settings.minimumBalance : account.settings.maximumBalance).formatted(.currency(code: account.currencyCode).precision(.fractionLength(0...8))))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: { Image(systemName: "bell.badge") }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                Section("Accounts") {
                    ForEach(viewModel.accounts) { account in
                        Button { editingAccount = account } label: {
                            HStack(spacing: 14) {
                                Image(systemName: account.type.symbol)
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(account.settings.color.tint, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.name).font(.headline)
                                    Text(account.type.title).font(.subheadline).foregroundStyle(.secondary)
                                    Text(account.settings.currentBalance, format: .currency(code: account.currencyCode).precision(.fractionLength(0...8)))
                                        .font(.headline).monospacedDigit()
                                    if account.settings.excludeFromStats {
                                        Text("Excluded from stats").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edit account")
                    }
                }
            }
            .overlay {
                if viewModel.accounts.isEmpty {
                    if viewModel.isLoading {
                        ProgressView("Loading accounts…")
                    } else {
                        ContentUnavailableView {
                            Label("Your wallet starts here", systemImage: "wallet.bifold")
                        } description: {
                            Text("Create your first account to organize your money.")
                        } actions: {
                            Button("Create Account") { isCreatingAccount = true }
                                .buttonStyle(.borderedProminent)
                        }
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
            .sheet(item: $editingAccount) { AccountEditorView(viewModel: viewModel, account: $0) }
            .alert("Unable to Load Accounts", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("Retry") { Task { await viewModel.reload() } }
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
        .task { await viewModel.observe() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.reload() } }
        }
    }
}
