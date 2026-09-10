import SwiftUI
import WalletDomain

struct RecurringView: View {
    @ObservedObject var viewModel: PlanningViewModel
    var body: some View {
        List {
            if viewModel.series.isEmpty {
                Text("Turn on Repeat when adding a record to create a recurring series.")
            }
            ForEach(viewModel.series) { series in
                NavigationLink {
                    RecurringDetailView(viewModel: viewModel, seriesID: series.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(series.template.payee.isEmpty ? viewModel.records.categoryTitle(series.template.categoryID) : series.template.payee).font(.headline)
                        Text("\(series.rule.frequency.rawValue.capitalized) · \(series.state.rawValue.capitalized)").font(.caption)
                        if let date = series.nextDate { Text("Next: \(date.formatted())").font(.caption).foregroundStyle(.secondary) }
                        else { Text("Series complete").font(.caption) }
                    }
                }
            }
            Section {
                Button("Generate Due Records Now") { Task { await viewModel.refresh(generate: true) } }
                    .disabled(viewModel.isLoading)
                Text("Catch-up processes up to 500 occurrences per series at a time. Saved occurrences can be changed or deleted in Records without being regenerated.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Recurring")
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
                Section("Series") {
                    Text(series.state.rawValue.capitalized)
                    Button("Edit Future Record Details") { editingTemplate = true }
                    Button("Edit Schedule") { editingSchedule = true }
                    Button(series.state == .active ? "Pause" : "Resume") {
                        var updated = series
                        updated.state = series.state == .active ? .paused : .active
                        save(updated)
                    }.disabled(series.state == .cancelled)
                    Button("Cancel Series", role: .destructive) { confirmingCancel = true }.disabled(series.state == .cancelled)
                }
                Section("Upcoming occurrences") {
                    if series.state != .active { Text("No automatic records while \(series.state.rawValue).") }
                    ForEach(upcoming(series)) { occurrence in
                        let date = occurrence.overrideDraft?.date ?? series.rule.date(start: series.startDate, index: occurrence.index)!
                        VStack(alignment: .leading) {
                            Text(date.formatted())
                            Text(occurrence.skipped ? "Skipped" : (occurrence.overrideDraft == nil ? "Scheduled" : "Modified"))
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Modify") { editingOccurrence = occurrence }
                                Button(occurrence.skipped ? "Restore" : "Skip") {
                                    var updated = occurrence
                                    updated.skipped.toggle()
                                    Task { do { try await viewModel.save(updated) } catch { viewModel.errorMessage = error.localizedDescription } }
                                }
                            }.buttonStyle(.bordered)
                        }
                    }
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
