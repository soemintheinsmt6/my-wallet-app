import SwiftUI
import WalletDomain

/// One account on its own: balance, a period's income and expenses, and the records that touched
/// it. This is where narrowing to a single account lives, now that the dashboard always shows the
/// whole wallet.
struct AccountDetailView: View {
    @ObservedObject var accounts: AccountsViewModel
    @ObservedObject var records: RecordsViewModel
    let accountID: UUID
    @State private var period = ActivityPeriod.month
    /// Any date inside the period being shown; the arrows move it a period at a time.
    @State private var anchor = Date()
    @State private var editingAccount: Account?
    @State private var editingRecord: WalletRecord?

    /// Read live, so an edit or a new record shows without leaving the screen.
    private var account: Account? { records.account(accountID) }
    private var interval: DateInterval { period.interval(containing: anchor) }
    private var activity: AccountActivity {
        AccountActivity(records: records.records, accountID: accountID, interval: interval)
    }
    private var isCurrentPeriod: Bool { interval.contains(Date()) }

    var body: some View {
        Group {
            if let account {
                List {
                    header(account)
                    periodSection
                    let activity = activity
                    Section {
                        WalletSummaryCard(income: activity.income, expenses: activity.expenses,
                                          currencyCode: account.currencyCode)
                    } footer: {
                        WalletListFooter("Transfers between your accounts are listed below but not counted as income or expenses.")
                    }
                    recordsSection(activity.records)
                }
                .listStyle(.plain)
            } else {
                WalletEmptyState(title: "Account unavailable", symbol: "questionmark.folder",
                                 message: "It may have been deleted on another device.")
            }
        }
        .navigationTitle(account?.name ?? "Account")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let account {
                ToolbarItem {
                    Button("Edit") { editingAccount = account }
                }
            }
        }
        .sheet(item: $editingAccount) { AccountEditorView(viewModel: accounts, account: $0) }
        .sheet(item: $editingRecord) { RecordEditorView(viewModel: records, record: $0) }
        .onChange(of: period) { _, _ in anchor = Date() }
    }

    private func header(_ account: Account) -> some View {
        Section {
            HStack(spacing: WalletMetrics.medium) {
                WalletIconTile(symbol: account.symbol, color: account.settings.color.tint, large: true)
                VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                    Text("Balance")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(account.settings.currentBalance.walletFormatted(account.currencyCode))
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(account.settings.currentBalance < 0 ? .red : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(account.settings.excludeFromStats
                         ? "\(account.type.title) · Excluded from stats" : account.type.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, WalletMetrics.small)
            .accessibilityElement(children: .combine)
            .walletFirstRow(true)
            .listRowSeparator(.hidden, edges: .bottom)
        }
    }

    private var periodSection: some View {
        Section {
            Picker("Period", selection: $period) {
                ForEach(ActivityPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowSeparator(.hidden)

            HStack {
                Button { shift(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: WalletMetrics.touchTarget, minHeight: WalletMetrics.touchTarget)
                }
                .accessibilityLabel("Previous \(period.title.lowercased())")
                Spacer()
                Text(periodTitle).font(.headline)
                Spacer()
                Button { shift(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(minWidth: WalletMetrics.touchTarget, minHeight: WalletMetrics.touchTarget)
                }
                // Nothing has happened after the current period yet.
                .disabled(isCurrentPeriod)
                .accessibilityLabel("Next \(period.title.lowercased())")
            }
            .buttonStyle(.borderless)
            .listRowSeparator(.hidden)
        }
    }

    private var periodTitle: String {
        let start = interval.start
        switch period {
        case .day:
            return isCurrentPeriod ? "Today" : start.formatted(date: .abbreviated, time: .omitted)
        case .week:
            let end = interval.end.addingTimeInterval(-1)
            return "\(start.formatted(.dateTime.month().day())) – \(end.formatted(.dateTime.month().day()))"
        case .month:
            return start.formatted(.dateTime.month(.wide).year())
        case .year:
            return start.formatted(.dateTime.year())
        }
    }

    private func shift(by value: Int) {
        guard let moved = Calendar.current.date(byAdding: period.component, value: value, to: anchor) else { return }
        anchor = moved
    }

    private func recordsSection(_ list: [WalletRecord]) -> some View {
        Section {
            if list.isEmpty {
                Text("No records in this period.")
                    .foregroundStyle(.secondary)
            }
            ForEach(list) { record in
                Button { editingRecord = record } label: {
                    RecordRow(viewModel: records, record: record, showsDate: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(list.count == 1 ? "1 record" : "\(list.count) records")
        }
    }
}
