import SwiftUI
import WalletDomain

/// The single-choice filters the statistics charts apply. `nil` means no limit.
struct StatisticsFilterSelection: Equatable {
    var currency: String
    var accountID: UUID?
    var categoryID: UUID?
    var tagID: UUID?

    var hasFilters: Bool { accountID != nil || categoryID != nil || tagID != nil }
}

/// Edits a private copy of the filters so a cancelled sheet leaves the charts untouched.
struct StatisticsFilterView: View {
    @ObservedObject var viewModel: RecordsViewModel
    /// Accounts included in statistics; only these can be filtered on.
    let accounts: [Account]
    @Binding var selection: StatisticsFilterSelection
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StatisticsFilterSelection
    @State private var choosingCategory = false

    init(viewModel: RecordsViewModel, accounts: [Account], selection: Binding<StatisticsFilterSelection>) {
        self.viewModel = viewModel
        self.accounts = accounts
        _selection = selection
        _draft = State(initialValue: selection.wrappedValue)
    }

    private var currencies: [String] { Array(Set(accounts.map(\.currencyCode))).sorted() }

    var body: some View {
        NavigationStack {
            Form {
                if currencies.count > 1 {
                    Section {
                        ForEach(currencies, id: \.self) { code in
                            choiceRow(code, isOn: draft.currency == code) { chooseCurrency(code) }
                        }
                    } header: { Text("Currency") } footer: {
                        Text("Totals stay separate per currency.")
                    }
                }
                Section("Account") {
                    choiceRow("All included accounts", symbol: "tray.full.fill", tint: .secondary,
                              isOn: draft.accountID == nil) { draft.accountID = nil }
                    ForEach(accounts.filter { $0.currencyCode == draft.currency }) { account in
                        AccountSymbolReader(account: account) { symbol in
                            choiceRow(account.name, symbol: symbol, tint: account.settings.color.tint,
                                      isOn: draft.accountID == account.id) { draft.accountID = account.id }
                        }
                    }
                }
                Section {
                    Button { choosingCategory = true } label: {
                        HStack(spacing: WalletMetrics.small) {
                            Text("Category").foregroundStyle(.primary)
                            Spacer(minLength: WalletMetrics.small)
                            Text(viewModel.category(draft.categoryID)?.name ?? "All categories")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            WalletDisclosure()
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("Category and label filters affect activity charts only.")
                }
                Section("Label") {
                    choiceRow("All labels", symbol: "tag", tint: .secondary,
                              isOn: draft.tagID == nil) { draft.tagID = nil }
                    ForEach(viewModel.tags) { tag in
                        choiceRow(tag.name, symbol: "tag.fill", tint: tag.color.tint,
                                  isOn: draft.tagID == tag.id) { draft.tagID = tag.id }
                    }
                }
                Section {
                    Button("Clear All Filters", role: .destructive) {
                        draft.accountID = nil
                        draft.categoryID = nil
                        draft.tagID = nil
                    }
                    .disabled(!draft.hasFilters)
                }
            }
            .navigationTitle("Filters")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(isPresented: $choosingCategory) {
                StatisticsCategoryFilterList(viewModel: viewModel, selection: $draft.categoryID) {
                    choosingCategory = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { selection = draft; dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    /// An account belongs to one currency, so switching currency drops an account from another.
    private func chooseCurrency(_ code: String) {
        draft.currency = code
        if let account = accounts.first(where: { $0.id == draft.accountID }), account.currencyCode != code {
            draft.accountID = nil
        }
    }

    private func choiceRow(_ title: String, symbol: String? = nil, tint: Color = .secondary,
                           isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if let symbol { Image(systemName: symbol).foregroundStyle(tint).frame(width: 24) }
                Text(title).foregroundStyle(.primary).lineLimit(1)
                Spacer()
                if isOn { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Categories grouped under their parent, searchable. Choosing one returns to the filters.
private struct StatisticsCategoryFilterList: View {
    @ObservedObject var viewModel: RecordsViewModel
    @Binding var selection: UUID?
    let onPicked: () -> Void
    @State private var search = ""

    var body: some View {
        List {
            if search.isEmpty {
                Section {
                    row(title: "All categories", category: nil)
                } footer: {
                    Text("Choosing a category also includes its subcategories.")
                }
            }
            ForEach(viewModel.categories.filter { $0.parentID == nil }) { root in
                let children = viewModel.categories.filter { $0.parentID == root.id }
                let matchesRoot = search.isEmpty || root.name.localizedCaseInsensitiveContains(search)
                let matches = matchesRoot ? children : children.filter { $0.name.localizedCaseInsensitiveContains(search) }
                if matchesRoot || !matches.isEmpty {
                    Section(root.name) {
                        if matchesRoot { row(title: root.name, category: root) }
                        ForEach(matches) { child in row(title: child.name, category: child).padding(.leading, 12) }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Category or subcategory")
        .navigationTitle("Category")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func row(title: String, category: WalletCategory?) -> some View {
        let isOn = selection == category?.id
        return Button {
            selection = category?.id
            onPicked()
        } label: {
            HStack {
                if let category {
                    CategoryIcon(category: category)
                } else {
                    Image(systemName: "square.grid.2x2").foregroundStyle(.secondary).frame(width: 24)
                }
                Text(title).foregroundStyle(.primary).lineLimit(1)
                Spacer()
                if isOn { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
