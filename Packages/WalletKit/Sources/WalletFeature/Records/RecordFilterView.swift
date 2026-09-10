import SwiftUI
import WalletDomain

/// Edits a private copy of the query so a cancelled sheet leaves the visible results untouched.
struct RecordFilterView: View {
    @ObservedObject var viewModel: RecordsViewModel
    @Binding var query: RecordQuery
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecordQuery
    @State private var limitsDates: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var minimum: String
    @State private var maximum: String

    init(viewModel: RecordsViewModel, query: Binding<RecordQuery>) {
        self.viewModel = viewModel
        _query = query
        let value = query.wrappedValue
        _draft = State(initialValue: value)
        _limitsDates = State(initialValue: value.start != nil || value.end != nil)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        _start = State(initialValue: value.start ?? calendar.date(byAdding: .month, value: -1, to: today) ?? today)
        // A stored end is the exclusive start of the following day; show the last included day.
        _end = State(initialValue: value.end.map { calendar.date(byAdding: .day, value: -1, to: $0) ?? $0 } ?? today)
        _minimum = State(initialValue: value.minimumAmount.map { AccountAmountInput.text($0) } ?? "")
        _maximum = State(initialValue: value.maximumAmount.map { AccountAmountInput.text($0) } ?? "")
    }

    private var minimumAmount: Decimal? { try? AccountAmountInput.parse(minimum) }
    private var maximumAmount: Decimal? { try? AccountAmountInput.parse(maximum) }
    private var amountError: String? {
        if !minimum.isEmpty, minimumAmount == nil { return "Enter a valid minimum amount, or leave it empty." }
        if !maximum.isEmpty, maximumAmount == nil { return "Enter a valid maximum amount, or leave it empty." }
        if let low = minimumAmount, let high = maximumAmount, low > high {
            return "The minimum amount must not be greater than the maximum."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sort results by") {
                    Picker("Sort", selection: $draft.sort) {
                        ForEach(RecordSortOrder.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    if draft.sort == .relevance, !draft.hasText {
                        Text("Without search text, relevance shows the newest records first.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Type") {
                    ForEach(RecordKind.allCases) { kind in
                        toggleRow(kind.title, symbol: kind.symbol, tint: kind.tint,
                                  isOn: draft.kinds.contains(kind)) { toggle(kind, in: &draft.kinds) }
                    }
                }
                Section {
                    ForEach(viewModel.accounts) { account in
                        toggleRow(account.name, symbol: account.type.symbol, tint: account.settings.color.tint,
                                  detail: account.currencyCode,
                                  isOn: draft.accountIDs.contains(account.id)) { toggle(account.id, in: &draft.accountIDs) }
                    }
                    if viewModel.accounts.isEmpty { Text("No accounts yet.").foregroundStyle(.secondary) }
                } header: { Text("Accounts") } footer: {
                    Text("A transfer matches when either of its accounts is selected.")
                }
                Section {
                    NavigationLink {
                        RecordFilterCategoryList(viewModel: viewModel, selection: $draft.categoryIDs)
                    } label: {
                        LabeledContent("Categories", value: summary(count: draft.categoryIDs.count, all: "All categories"))
                    }
                    NavigationLink {
                        RecordFilterPaymentList(selection: $draft.paymentTypes)
                    } label: {
                        LabeledContent("Payment type", value: summary(count: draft.paymentTypes.count, all: "Any payment type"))
                    }
                }
                Section("Labels") {
                    ForEach(viewModel.tags) { tag in
                        toggleRow(tag.name, symbol: "tag.fill", tint: tag.color.tint,
                                  isOn: draft.tagIDs.contains(tag.id)) { toggle(tag.id, in: &draft.tagIDs) }
                    }
                    if viewModel.tags.isEmpty { Text("No labels yet.").foregroundStyle(.secondary) }
                }
                Section("Date") {
                    Toggle("Limit to a date range", isOn: $limitsDates)
                    if limitsDates {
                        DatePicker("From", selection: $start, displayedComponents: .date)
                        DatePicker("Through", selection: $end, in: start..., displayedComponents: .date)
                    }
                }
                Section {
                    LabeledContent("Minimum") {
                        amountField("Any", text: $minimum)
                    }
                    LabeledContent("Maximum") {
                        amountField("Any", text: $maximum)
                    }
                    if let amountError { Text(amountError).font(.caption).foregroundStyle(.red) }
                } header: { Text("Amount") } footer: {
                    Text("Amounts compare against the record's own amount, before any currency conversion.")
                }
                Section {
                    Button("Clear All Filters", role: .destructive) { draft.clearFilters(); limitsDates = false; minimum = ""; maximum = "" }
                        .disabled(draft.activeFilterCount == 0)
                }
            }
            .navigationTitle("Filters")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }.disabled(amountError != nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private func apply() {
        var value = draft
        if limitsDates {
            let calendar = Calendar.current
            let from = calendar.startOfDay(for: start)
            value.start = from
            value.end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(start, end)))
        } else {
            value.start = nil
            value.end = nil
        }
        value.minimumAmount = minimum.isEmpty ? nil : minimumAmount
        value.maximumAmount = maximum.isEmpty ? nil : maximumAmount
        query = value
        dismiss()
    }

    private func toggle<Value: Hashable>(_ value: Value, in selection: inout Set<Value>) {
        if selection.contains(value) { selection.remove(value) } else { selection.insert(value) }
    }

    private func summary(count: Int, all: String) -> String {
        count == 0 ? all : "\(count) selected"
    }

    private func amountField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .multilineTextAlignment(.trailing)
            #if !os(macOS)
            .keyboardType(.decimalPad)
            #endif
    }

    private func toggleRow(_ title: String, symbol: String, tint: Color, detail: String? = nil,
                           isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 24)
                Text(title).foregroundStyle(.primary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
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

struct RecordFilterCategoryList: View {
    @ObservedObject var viewModel: RecordsViewModel
    @Binding var selection: Set<UUID>
    @State private var search = ""

    var body: some View {
        List {
            Section {
                Text("Selecting a category also includes its subcategories. Records without a category are excluded while a category filter is active.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(viewModel.categories.filter { $0.parentID == nil }) { root in
                let children = viewModel.categories.filter { $0.parentID == root.id }
                let matchesRoot = search.isEmpty || root.name.localizedCaseInsensitiveContains(search)
                let matches = matchesRoot ? children : children.filter { $0.name.localizedCaseInsensitiveContains(search) }
                if matchesRoot || !matches.isEmpty {
                    Section(root.name) {
                        if matchesRoot { row(root) }
                        ForEach(matches) { child in row(child).padding(.leading, 12) }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Category or subcategory")
        .navigationTitle("Categories")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear") { selection = [] }.disabled(selection.isEmpty)
            }
        }
    }

    private func row(_ category: WalletCategory) -> some View {
        Button {
            if selection.contains(category.id) { selection.remove(category.id) } else { selection.insert(category.id) }
        } label: {
            HStack {
                CategoryIcon(category: category)
                Text(category.name).foregroundStyle(.primary)
                Spacer()
                if selection.contains(category.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection.contains(category.id) ? .isSelected : [])
    }
}

struct RecordFilterPaymentList: View {
    @Binding var selection: Set<PaymentType>

    var body: some View {
        List(PaymentType.allCases) { type in
            Button {
                if selection.contains(type) { selection.remove(type) } else { selection.insert(type) }
            } label: {
                HStack {
                    Text(type.title).foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(type) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection.contains(type) ? .isSelected : [])
        }
        .navigationTitle("Payment type")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

extension RecordSortOrder {
    var title: String {
        switch self {
        case .relevance: "Relevance"
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .largest: "Largest amount"
        case .smallest: "Smallest amount"
        }
    }
}
