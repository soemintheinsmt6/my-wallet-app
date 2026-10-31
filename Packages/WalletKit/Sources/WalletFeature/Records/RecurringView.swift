import SwiftUI
import WalletDomain

struct RecurringView: View {
    @ObservedObject var viewModel: PlanningViewModel

    var body: some View {
        List {
            if !viewModel.series.isEmpty {
                // Untitled: the page is already Recurring, so a "Series" heading only repeated it.
                Section {
                    ForEach(viewModel.series) { series in
                        NavigationLink {
                            RecurringDetailView(viewModel: viewModel, seriesID: series.id)
                        } label: {
                            row(series)
                        }
                    }
                }
                .listSectionSeparator(.hidden, edges: .top)
                // Only with a series to generate from; otherwise it sat above the empty state.
                Section {
                    Button {
                        Task { await viewModel.refresh(generate: true) }
                    } label: {
                        Label("Generate Due Records Now", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                } footer: {
                    WalletListFooter("Catch-up processes up to 500 occurrences per series at a time. Saved occurrences can be changed or deleted in Records without being regenerated.")
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.series.isEmpty {
                WalletEmptyState(title: "No recurring records", symbol: "repeat",
                                 message: "Turn on Repeat when adding a record to create a recurring series.")
            }
        }
        .navigationTitle("Recurring")
    }

    private func row(_ series: RecurringSeries) -> some View {
        let title = series.template.payee.isEmpty
            ? viewModel.records.categoryName(series.template.categoryID)
            : series.template.payee
        return HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: "repeat", color: tint(for: series.state))
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                HStack(spacing: WalletMetrics.small) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if series.state != .active {
                        WalletBadge(title: series.state.rawValue.capitalized,
                                    tint: tint(for: series.state),
                                    accessibilityPrefix: "Status")
                            .fixedSize()
                    }
                }
                Text(detail(series))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: WalletMetrics.small)
            WalletAmountText(amount: series.template.amount,
                             currencyCode: viewModel.records.account(series.template.accountID)?.currencyCode ?? "USD",
                             kind: series.template.kind, font: .subheadline.weight(.semibold))
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .padding(.vertical, WalletMetrics.tight)
    }

    private func detail(_ series: RecurringSeries) -> String {
        let frequency = series.rule.frequency.rawValue.capitalized
        guard let next = series.nextDate else { return "\(frequency) · Series complete" }
        // The year only when it differs from this one, so the line fits beside the amount.
        let sameYear = Calendar.current.isDate(next, equalTo: Date(), toGranularity: .year)
        let date = sameYear ? next.formatted(.dateTime.day().month(.abbreviated))
                            : next.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(frequency) · Next \(date)"
    }

    private func tint(for state: SeriesState) -> Color {
        switch state {
        case .active: .indigo
        case .paused: .orange
        case .cancelled: .gray
        }
    }
}

private struct RecurringDetailView: View {
    @ObservedObject var viewModel: PlanningViewModel
    let seriesID: UUID
    @State private var editingTemplate = false
    @State private var editingSchedule = false
    @State private var editingOccurrence: ScheduledOccurrence?
    @State private var confirmingCancel = false
    private var series: RecurringSeries? { viewModel.series.first { $0.id == seriesID } }

    var body: some View {
        List {
            if let series {
                Section {
                    LabeledContent("Status") {
                        WalletBadge(title: series.state.rawValue.capitalized,
                                    tint: series.state == .active ? .green : series.state == .paused ? .orange : .gray,
                                    accessibilityPrefix: "Status")
                    }
                    LabeledContent("Repeats", value: series.rule.frequency.rawValue.capitalized)
                    if let next = series.nextDate {
                        LabeledContent("Next record", value: next.formatted(date: .abbreviated, time: .shortened))
                    }
                } header: {
                    Text("Series")
                }

                Section("Actions") {
                    Button { editingTemplate = true } label: {
                        Label("Edit Future Record Details", systemImage: "square.and.pencil")
                    }
                    Button { editingSchedule = true } label: {
                        Label("Edit Schedule", systemImage: "calendar")
                    }
                    Button {
                        var updated = series
                        updated.state = series.state == .active ? .paused : .active
                        save(updated)
                    } label: {
                        Label(series.state == .active ? "Pause Series" : "Resume Series",
                              systemImage: series.state == .active ? "pause.circle" : "play.circle")
                    }
                    .disabled(series.state == .cancelled)
                    Button(role: .destructive) { confirmingCancel = true } label: {
                        Label("Cancel Series", systemImage: "xmark.circle")
                    }
                    .disabled(series.state == .cancelled)
                }

                Section {
                    if series.state != .active {
                        Label("No automatic records while \(series.state.rawValue).", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(upcoming(series)) { occurrence in
                        occurrenceRow(occurrence, in: series)
                    }
                } header: {
                    Text("Upcoming occurrences")
                } footer: {
                    Text("Swipe an occurrence to skip it or restore it. Modify opens the record editor for that date only.")
                }
            }
        }
        .navigationTitle("Recurring Series")
        .disabled(viewModel.isSaving)
        .sheet(isPresented: $editingTemplate) {
            if let series {
                RecordEditorView(viewModel: viewModel.records, record: preview(series.template), title: "Future Record Details", allowsRecurrence: false) { _, draft in
                    var updated = series
                    updated.template = draft
                    try await viewModel.save(updated)
                }
            }
        }
        .sheet(isPresented: $editingSchedule) {
            if let series { SeriesScheduleEditor(viewModel: viewModel, series: series) }
        }
        .sheet(item: $editingOccurrence) { occurrence in
            if let series {
                var draft = occurrence.overrideDraft ?? series.template
                let _ = draft.date = occurrence.overrideDraft?.date ?? series.rule.date(start: series.startDate, index: occurrence.index)!
                RecordEditorView(viewModel: viewModel.records, record: preview(draft), title: "Modify Occurrence", allowsRecurrence: false) { _, values in
                    var updated = occurrence
                    updated.overrideDraft = values
                    updated.skipped = false
                    try await viewModel.save(updated)
                }
            }
        }
        .alert("Cancel Series?", isPresented: $confirmingCancel) {
            Button("Keep Series", role: .cancel) {}
            Button("Cancel Series", role: .destructive) {
                guard var updated = series else { return }
                updated.state = .cancelled
                save(updated)
            }
        } message: { Text("Future automatic records stop. Existing records are kept.") }
    }

    private func occurrenceRow(_ occurrence: ScheduledOccurrence, in series: RecurringSeries) -> some View {
        let date = occurrence.overrideDraft?.date ?? series.rule.date(start: series.startDate, index: occurrence.index)!
        let state = occurrence.skipped ? "Skipped" : occurrence.overrideDraft == nil ? "Scheduled" : "Modified"
        return HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: occurrence.skipped ? "minus.circle" : "calendar",
                           color: occurrence.skipped ? .gray : .indigo)
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.body.weight(.medium))
                    .foregroundStyle(occurrence.skipped ? Color.secondary : Color.primary)
                Text(state)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: WalletMetrics.small)
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .padding(.vertical, WalletMetrics.tight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .leading) {
            Button("Modify", systemImage: "pencil") { editingOccurrence = occurrence }.tint(.blue)
        }
        .swipeActions {
            Button(occurrence.skipped ? "Restore" : "Skip",
                   systemImage: occurrence.skipped ? "arrow.uturn.backward" : "minus.circle") {
                var updated = occurrence
                updated.skipped.toggle()
                Task { do { try await viewModel.save(updated) } catch { viewModel.errorMessage = error.localizedDescription } }
            }
            .tint(occurrence.skipped ? .green : .orange)
        }
        .contextMenu {
            Button("Modify", systemImage: "pencil") { editingOccurrence = occurrence }
            Button(occurrence.skipped ? "Restore" : "Skip",
                   systemImage: occurrence.skipped ? "arrow.uturn.backward" : "minus.circle") {
                var updated = occurrence
                updated.skipped.toggle()
                Task { do { try await viewModel.save(updated) } catch { viewModel.errorMessage = error.localizedDescription } }
            }
        }
    }

    private func upcoming(_ series: RecurringSeries) -> [ScheduledOccurrence] {
        let pending = viewModel.occurrences.filter { $0.seriesID == series.id && !$0.completed && $0.index < series.nextIndex }
        let upcoming = (series.nextIndex..<(series.nextIndex + 12)).compactMap { index -> ScheduledOccurrence? in
            guard series.rule.date(start: series.startDate, index: index) != nil else { return nil }
            return viewModel.occurrences.first { $0.seriesID == series.id && $0.index == index }
                ?? ScheduledOccurrence(seriesID: series.id, index: index)
        }
        return pending + upcoming.filter { !$0.completed }
    }
    private func preview(_ draft: RecordDraft) -> WalletRecord {
        WalletRecord(id: UUID(), draft: draft, currencyCode: viewModel.records.account(draft.accountID)?.currencyCode ?? "USD")
    }
    private func save(_ series: RecurringSeries) {
        Task { do { try await viewModel.save(series) } catch { viewModel.errorMessage = error.localizedDescription } }
    }
}

private struct SeriesScheduleEditor: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State var series: RecurringSeries
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Text("Original start: \(series.startDate.formatted())")
                RecurrenceFields(rule: Binding(get: { series.rule }, set: { if let rule = $0 { series.rule = rule } }), start: series.startDate, allowDisabling: false)
                Text("Changes apply to unprocessed occurrences. Counts include the original record. Resuming catches up missed dates.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Schedule")
            .disabled(viewModel.isSaving)
            .toolbar {
                Button("Cancel") { dismiss() }.disabled(viewModel.isSaving)
                Button("Save") {
                    Task { do { try await viewModel.save(series); dismiss() } catch { self.error = error.localizedDescription } }
                }.disabled(viewModel.isSaving)
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }
}
