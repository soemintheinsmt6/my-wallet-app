import SwiftUI
import WalletDomain

public struct RecordsView: View {
    @ObservedObject private var viewModel: RecordsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var creating = false
    @State private var pendingDelete: WalletRecord?
    @State private var deletionError: String?
    @State private var query = RecordQuery()
    @State private var filtering = false
    @State private var editingRecord: WalletRecord?
    @AppStorage(WalletPreferenceKeys.recentSearches) private var recentSearches = ""

    public init(viewModel: RecordsViewModel) { self.viewModel = viewModel }

    private var results: [RecordSearchResult] {
        RecordSearch.run(records: viewModel.records, categories: viewModel.categories,
                         tags: viewModel.tags, query: query)
    }

    public var body: some View {
        let matches = results
        let grouped = RecordDayGrouping.groups(query.sort, hasText: query.hasText)
        return NavigationStack {
            List {
                if query.isActive { summarySection(for: matches.count) }
                if grouped {
                    let byDate = RecordDayGrouping.daysByDate(query.sort, hasText: query.hasText)
                    ForEach(RecordDayGrouping.sections(for: matches, newestDayFirst: byDate)) { section in
                        Section {
                            ForEach(section.results) { row($0.record) }
                        } header: {
                            dayHeader(section)
                        }
                    }
                } else {
                    ForEach(matches) { row($0.record) }
                }
            }
            // Edge-to-edge rows rather than inset cards.
            .listStyle(.plain)
            .searchable(text: $query.text, prompt: "Note, payee, amount, category or label")
            .searchSuggestions { suggestions }
            .onSubmit(of: .search) { recentSearches = RecentSearches.adding(query.text, to: recentSearches) }
            .alert("Delete Record?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Delete", role: .destructive) {
                    guard let record = pendingDelete else { return }
                    pendingDelete = nil
                    Task {
                        do { try await viewModel.delete(id: record.id) }
                        catch { deletionError = error.localizedDescription }
                    }
                }
            } message: { Text("This removes the record and its photo and reverses its effect on account balances.") }
            .alert("Unable to Delete Record", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
                Button("OK", role: .cancel) { deletionError = nil }
            } message: { Text(deletionError ?? "") }
            .overlay {
                if viewModel.records.isEmpty {
                    if viewModel.isLoading {
                        WalletLoadingState(message: "Loading records…")
                    } else if viewModel.accounts.isEmpty {
                        WalletEmptyState(title: "No records yet", symbol: "list.bullet.rectangle",
                                         message: "Create an account first, then add an expense, income, or transfer.")
                    } else {
                        WalletEmptyState(title: "No records yet", symbol: "list.bullet.rectangle",
                                         message: "Add an expense, income, or transfer.",
                                         actionTitle: "Add Record") { creating = true }
                    }
                } else if matches.isEmpty {
                    WalletEmptyState(
                        title: "No matching records", symbol: "magnifyingglass",
                        message: query.hasText
                            ? "No record matches “\(query.text)” with the current filters."
                            : "No record matches the current filters.",
                        actionTitle: "Clear Search and Filters") { clear() }
                }
            }
            .navigationTitle("Records")
            .toolbar {
                ToolbarItem { sortMenu }
                ToolbarItem {
                    Button { filtering = true } label: {
                        Label("Filters", systemImage: query.activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityValue(query.activeFilterCount == 0 ? "No filters" : "\(query.activeFilterCount) filters applied")
                }
                WalletToolbarSeparator()
                ToolbarItem {
                    Button { creating = true } label: { Label("Add Record", systemImage: "plus") }
                        .disabled(viewModel.accounts.isEmpty || viewModel.isLoading)
                }
            }
            .sheet(isPresented: $creating) { RecordEditorView(viewModel: viewModel) }
            .sheet(isPresented: $filtering) { RecordFilterView(viewModel: viewModel, query: $query) }
            .sheet(item: $editingRecord) { RecordEditorView(viewModel: viewModel, record: $0) }
            .refreshable { await viewModel.reload() }
            .alert("Unable to Load Records", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("Retry") { Task { await viewModel.reload() } }
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
        .task { await viewModel.observe() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await viewModel.reload() } } }
    }

    // MARK: - Pieces

    private func summarySection(for count: Int) -> some View {
        Section {
            HStack {
                Label(summary(for: count), systemImage: "line.3.horizontal.decrease")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { clear() }
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private func dayHeader(_ section: RecordDaySection) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(dayTitle(section.date))
            Spacer(minLength: WalletMetrics.small)
            if let net = section.net, let currency = section.currencyCode {
                WalletAmountText.net(net, currencyCode: currency, font: .caption.weight(.semibold))
                    .textCase(nil)
            }
        }
    }

    /// Today and Yesterday read faster than a date; older days keep the weekday for orientation.
    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide).month().day())
        }
        return date.formatted(.dateTime.year().month().day())
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $query.sort) {
                ForEach(RecordSortOrder.allCases) { order in
                    Text(order.rawValue.capitalized).tag(order)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityValue("Sorted by \(query.sort.rawValue)")
    }

    @ViewBuilder private var suggestions: some View {
        let recents = RecentSearches.list(from: recentSearches)
        if query.text.isEmpty, !recents.isEmpty {
            Section("Recent searches") {
                ForEach(recents, id: \.self) { term in
                    Label(term, systemImage: "clock.arrow.circlepath").searchCompletion(term)
                }
                Button("Clear Recent Searches") { recentSearches = "" }
            }
        }
    }

    private func row(_ record: WalletRecord) -> some View {
        Button { editingRecord = record } label: {
            RecordRow(viewModel: viewModel, record: record)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Drag onto a category to refile the record; iPad and macOS only in practice.
        .draggable(RecordTransfer(recordID: record.id))
        .swipeActions {
            Button("Delete", role: .destructive) { pendingDelete = record }
        }
        .contextMenu {
            Button("Delete Record", role: .destructive) { pendingDelete = record }
        }
        .disabled(viewModel.isSaving)
    }

    private func summary(for count: Int) -> String {
        let records = count == 1 ? "1 record" : "\(count) records"
        guard query.activeFilterCount > 0 else { return records }
        let filters = query.activeFilterCount == 1 ? "1 filter" : "\(query.activeFilterCount) filters"
        return "\(records) · \(filters)"
    }

    private func clear() {
        query = RecordQuery(sort: query.sort)
    }
}
