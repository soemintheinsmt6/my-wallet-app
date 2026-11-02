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
        .sheet(item: Binding(get: { viewModel.plan.map(IdentifiedPlan.init) },
                             set: { if $0 == nil { viewModel.cancelImport() } })) { wrapper in
            ImportPreviewView(viewModel: viewModel, plan: wrapper.plan)
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
            Text("Records are matched to your existing accounts and categories by name, and you review everything before it is saved. Rows already in your wallet are skipped.")
        }
    }

    private func prepare(_ work: () throws -> Void) {
        exportError = nil
        do { try work() } catch { exportError = error.localizedDescription }
    }
}

/// `ImportPlan` is not `Identifiable`; this wraps it for `sheet(item:)`.
private struct IdentifiedPlan: Identifiable {
    let plan: ImportPlan
    let id = UUID()

    init(_ plan: ImportPlan) { self.plan = plan }
}

/// Shows what an import would do before anything is written.
private struct ImportPreviewView: View {
    @ObservedObject var viewModel: DataExchangeViewModel
    let plan: ImportPlan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
                                    Text(!entry.row.categoryPath.isEmpty ? entry.row.categoryPath
                                         : entry.row.isAdjustment ? RecordDraft.adjustmentTitle : entry.row.kind.title)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text("\(entry.row.accountName) · \(entry.row.date.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: WalletMetrics.small)
                                WalletAmountText(amount: entry.row.amount,
                                                 currencyCode: entry.row.currencyCode.isEmpty ? "USD" : entry.row.currencyCode,
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
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private func summary(_ title: String, count: Int, symbol: String, tint: Color) -> some View {
        LabeledContent {
            Text("\(count)").monospacedDigit().font(.body.weight(.semibold))
        } label: {
            Label(title, systemImage: symbol).foregroundStyle(tint)
        }
    }
}
