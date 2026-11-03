import SwiftUI
import UniformTypeIdentifiers
import WalletDomain

/// Export and import, reached from Settings.
public struct DataExchangeView: View {
    @ObservedObject private var viewModel: DataExchangeViewModel
    @State private var csvURL: URL?
    @State private var jsonURL: URL?
    @State private var isChoosingFile = false
    @State private var exportError: String?

    public init(viewModel: DataExchangeViewModel) { self.viewModel = viewModel }

    public var body: some View {
        List {
            exportSection
            importSection
            if let message = viewModel.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            if viewModel.importedCount > 0 {
                Section {
                    Label("Imported \(viewModel.importedCount) record\(viewModel.importedCount == 1 ? "" : "s").",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Export & Import")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .disabled(viewModel.isWorking)
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.commaSeparatedText, .text]) { result in
            switch result {
            case .success(let url): viewModel.prepareImport(from: url)
            case .failure(let error): viewModel.errorMessage = error.localizedDescription
            }
        }
        // Dismissing runs the Cancel button's action, so the binding never cancels on its own: it
        // may be set to false before an account button's action runs, which would drop the file.
        .confirmationDialog("Import into which account?", isPresented: Binding(
            get: { viewModel.needsAccountChoice }, set: { _ in }
        ), titleVisibility: .visible) {
            ForEach(viewModel.accountNames, id: \.self) { name in
                Button(name) { viewModel.chooseImportAccount(name) }
            }
            Button("Cancel", role: .cancel) { viewModel.cancelImport() }
        } message: {
            Text("This file has no Account column, as is usual for a bank statement. Every row will go into the account you choose.")
        }
        // Presented by whether a plan exists rather than by plan identity, so re-planning after a
        // sign flip updates the open sheet instead of replacing it.
        .sheet(isPresented: Binding(get: { viewModel.plan != nil },
                                    set: { if !$0 { viewModel.cancelImport() } })) {
            ImportPreviewView(viewModel: viewModel)
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                prepare { csvURL = try viewModel.exportCSV() }
            } label: {
                Label("Prepare CSV", systemImage: "tablecells")
            }
            if let csvURL {
                ShareLink(item: csvURL) { Label("Share CSV", systemImage: "square.and.arrow.up") }
            }

            Button {
                prepare { jsonURL = try viewModel.exportJSON() }
            } label: {
                Label("Prepare JSON Backup", systemImage: "doc.badge.gearshape")
            }
            if let jsonURL {
                ShareLink(item: jsonURL) { Label("Share JSON Backup", systemImage: "square.and.arrow.up") }
            }

            if let exportError {
                Label(exportError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
        } header: {
            Text("Export")
        } footer: {
            Text("CSV holds \(viewModel.recordCount) record\(viewModel.recordCount == 1 ? "" : "s") for spreadsheets. JSON keeps accounts, categories, labels and records with their identifiers for a full backup. Receipt images are not included in either.")
        }
    }

    private var importSection: some View {
        Section {
            Button {
                isChoosingFile = true
            } label: {
                Label("Import Records from CSV", systemImage: "square.and.arrow.down")
            }
            if viewModel.isWorking {
                HStack {
                    ProgressView()
                    Text(viewModel.progress.isEmpty ? "Working…" : viewModel.progress)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Import")
        } footer: {
            Text("Reads this app's CSV or a bank statement export with Debit/Credit columns or signed amounts. "
                 + "Rows are matched to your accounts and categories by name, and you review everything before it "
                 + "is saved. Rows already in your wallet are skipped.")
        }
    }

    private func prepare(_ work: () throws -> Void) {
        exportError = nil
        do { try work() } catch { exportError = error.localizedDescription }
    }
}

/// Shows what an import would do before anything is written.
private struct ImportPreviewView: View {
    @ObservedObject var viewModel: DataExchangeViewModel
    @Environment(\.dismiss) private var dismiss

    /// Kept after the plan clears, so the sheet does not go blank while it animates away.
    @State private var lastPlan = ImportPlan(entries: [])
    private var plan: ImportPlan { viewModel.plan ?? lastPlan }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.canReverseSigns {
                    Section {
                        Toggle("Amounts are spending", isOn: Binding(
                            get: { viewModel.importOptions.reversesSigns },
                            set: { viewModel.setReversesSigns($0) }))
                    } footer: {
                        Text("Turn on if spending shows as income below, as some card statements list purchases as positive amounts.")
                    }
                }

                let uncategorized = plan.uncategorizedKinds
                if !uncategorized.isEmpty {
                    Section {
                        ForEach([RecordKind.expense, .income].filter(uncategorized.contains)) { kind in
                            Picker(kind == .expense ? "Expenses" : "Income", selection: Binding(
                                get: { viewModel.fallbackCategoryIDs[kind] },
                                set: { viewModel.setFallbackCategory($0, for: kind) })) {
                                Text("Choose").tag(UUID?.none)
                                ForEach(viewModel.categoryChoices, id: \.id) { choice in
                                    Text(choice.path).tag(UUID?.some(choice.id))
                                }
                            }
                        }
                    } header: {
                        Text("Rows without a category")
                    } footer: {
                        Text("Income and expenses need a category. Rows the file doesn't categorise use these; you can change any record afterwards.")
                    }
                }

                Section {
                    summary("Ready to import", count: plan.importable.count, symbol: "checkmark.circle", tint: .green)
                    summary("Already in your wallet", count: plan.duplicates.count, symbol: "equal.circle", tint: .secondary)
                    summary("Cannot import", count: plan.problems.count, symbol: "exclamationmark.triangle", tint: .red)
                } header: {
                    Text("\(plan.entries.count) row\(plan.entries.count == 1 ? "" : "s") read")
                }

                if !plan.labelsToCreate.isEmpty {
                    Section("New labels") {
                        Text(plan.labelsToCreate.joined(separator: ", "))
                            .font(.callout)
                        Text("These labels do not exist yet and will be created in gray.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                let matched = plan.matchedToRecords
                if !matched.isEmpty {
                    Section {
                        ForEach(matched.prefix(20)) { entry in
                            matchedRow(entry)
                        }
                        if matched.count > 20 {
                            Text("and \(matched.count - 20) more.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Matched to your records")
                    } footer: {
                        Text("These rows match a record already in the account with the same amount, dated the same day "
                             + "or up to \(LedgerMatcher.postingLagDays) days earlier, and are skipped. "
                             + "Use Import Anyway for a purchase you never entered.")
                    }
                }

                if !plan.problems.isEmpty {
                    Section("Rows that cannot be imported") {
                        ForEach(plan.problems.prefix(20)) { entry in
                            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                                Text(entry.row.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.callout.weight(.medium))
                                Text(entry.issue?.message ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .padding(.vertical, WalletMetrics.hair)
                            .accessibilityElement(children: .combine)
                        }
                        if plan.problems.count > 20 {
                            Text("and \(plan.problems.count - 20) more.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !plan.importable.isEmpty {
                    Section("Preview") {
                        ForEach(plan.importable.prefix(10)) { entry in
                            HStack(spacing: WalletMetrics.medium) {
                                VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                                    Text(viewModel.previewTitle(for: entry))
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text("\(entry.row.accountName) · \(entry.row.date.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: WalletMetrics.small)
                                WalletAmountText(amount: entry.row.amount,
                                                 currencyCode: viewModel.currencyCode(for: entry),
                                                 kind: entry.row.kind, font: .callout.weight(.semibold))
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if plan.importable.count > 10 {
                            Text("and \(plan.importable.count - 10) more.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Review Import")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancelImport(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(plan.importable.count)") {
                        Task { await viewModel.applyImport(); dismiss() }
                    }
                    .disabled(plan.importable.isEmpty || viewModel.isWorking)
                }
            }
            .interactiveDismissDisabled(viewModel.isWorking)
            .onAppear { if let plan = viewModel.plan { lastPlan = plan } }
            .onChange(of: viewModel.plan) { _, plan in if let plan { lastPlan = plan } }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private func matchedRow(_ entry: ImportPlan.Entry) -> some View {
        HStack(spacing: WalletMetrics.medium) {
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(entry.row.payee.isEmpty ? viewModel.previewTitle(for: entry) : entry.row.payee)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(matchDescription(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                WalletAmountText(amount: entry.row.amount, currencyCode: viewModel.currencyCode(for: entry),
                                 kind: entry.row.kind, font: .caption.weight(.semibold))
            }
            Spacer(minLength: WalletMetrics.small)
            Button("Import Anyway") { viewModel.importAnyway(entry) }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
        }
        .padding(.vertical, WalletMetrics.hair)
    }

    private func matchDescription(_ entry: ImportPlan.Entry) -> String {
        let statement = entry.row.date.formatted(date: .abbreviated, time: .omitted)
        guard let recorded = entry.matchedRecordDate else { return statement }
        let same = Calendar.current.isDate(recorded, inSameDayAs: entry.row.date)
        return same ? "\(statement), matches your record that day"
            : "\(statement), matches your record on \(recorded.formatted(date: .abbreviated, time: .omitted))"
    }

    private func summary(_ title: String, count: Int, symbol: String, tint: Color) -> some View {
        LabeledContent {
            Text("\(count)").monospacedDigit().font(.body.weight(.semibold))
        } label: {
            Label(title, systemImage: symbol).foregroundStyle(tint)
        }
    }
}
