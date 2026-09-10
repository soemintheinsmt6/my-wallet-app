import Combine
import Foundation
import WalletDomain

/// Builds export files and applies CSV imports.
///
/// Reads the wallet through `RecordsViewModel` and writes through the same use cases the editors
/// use, so imported records go through the identical validation and balance handling.
@MainActor
public final class DataExchangeViewModel: ObservableObject {
    @Published public private(set) var isWorking = false
    @Published public private(set) var progress = ""
    @Published public var errorMessage: String?
    /// Set once a file has been parsed, so the UI can show a preview before anything is written.
    @Published public var plan: ImportPlan?
    @Published public private(set) var importedCount = 0

    private let records: RecordsViewModel
    private let recordUseCases: RecordUseCases
    private let tagUseCases: TagUseCases

    public init(records: RecordsViewModel, recordUseCases: RecordUseCases, tagUseCases: TagUseCases) {
        self.records = records
        self.recordUseCases = recordUseCases
        self.tagUseCases = tagUseCases
    }

    // MARK: - Export

    public var recordCount: Int { records.records.count }

    public func exportCSV() throws -> URL {
        let text = RecordCSV.export(records: records.records, accounts: records.accounts,
                                    categories: records.categories, tags: records.tags)
        // The BOM makes Excel open UTF-8 correctly instead of mangling accented names.
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(text.utf8))
        return try write(data, name: "My-Wallet-Records", extension: "csv")
    }

    public func exportJSON() throws -> URL {
        let archive = WalletArchive(accounts: records.accounts, categories: records.categories,
                                    tags: records.tags, records: records.records)
        return try write(try WalletArchive.encode(archive), name: "My-Wallet-Backup", extension: "json")
    }

    private func write(_ data: Data, name: String, extension ext: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WalletExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = directory.appendingPathComponent("\(name)-\(stamp).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Import

    /// Reads and plans a CSV without changing anything.
    public func prepareImport(from url: URL) {
        errorMessage = nil
        plan = nil
        importedCount = 0
        do {
            // Files handed over by the document picker live outside the app's sandbox.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let table = try CSV.parse(decodeText(data))
            guard let header = table.first else { throw CSVError.empty }
            let rows = try RecordCSV.rows(from: table, mapping: RecordCSV.mapping(header: header))
            plan = ImportPlanner.plan(rows: rows, accounts: records.accounts,
                                      categories: records.categories, tags: records.tags,
                                      existing: records.records)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Files exported from other tools are not always UTF-8.
    private func decodeText(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    public func cancelImport() {
        plan = nil
        errorMessage = nil
    }

    /// Writes the importable rows, creating any missing labels first.
    ///
    /// Rows are saved one at a time through `RecordUseCases`, so a row the domain rejects is
    /// reported without discarding the rows that already succeeded.
    public func applyImport() async {
        guard let plan, !isWorking else { return }
        isWorking = true
        defer { isWorking = false; progress = "" }
        errorMessage = nil

        do {
            for name in plan.labelsToCreate {
                progress = "Creating label \(name)…"
                try await tagUseCases.create(name: name, color: .gray)
            }
        } catch {
            errorMessage = "Labels could not be created: \(error.localizedDescription)"
            return
        }
        // Creation does not hand back the new label, so reload and match the names back to IDs.
        if !plan.labelsToCreate.isEmpty { await records.reload() }
        let tagIDsByName = Dictionary(records.tags.map { ($0.name.lowercased(), $0.id) },
                                      uniquingKeysWith: { first, _ in first })

        var imported = 0
        var failures: [String] = []
        let entries = plan.importable
        for (index, entry) in entries.enumerated() {
            progress = "Importing \(index + 1) of \(entries.count)…"
            var draft = RecordDraft()
            draft.kind = entry.row.kind
            draft.accountID = entry.accountID
            draft.destinationAccountID = entry.destinationAccountID
            draft.amount = entry.row.amount
            draft.categoryID = entry.categoryID
            draft.date = entry.row.date
            draft.payee = entry.row.payee
            draft.note = entry.row.note
            draft.paymentType = entry.row.paymentType
            draft.tagIDs = entry.tagIDs.union(entry.newLabelNames.compactMap { tagIDsByName[$0.lowercased()] })
            do {
                try await recordUseCases.create(id: UUID(), draft: draft)
                imported += 1
            } catch {
                failures.append("\(entry.row.date.formatted(date: .abbreviated, time: .shortened)): \(error.localizedDescription)")
            }
        }

        importedCount = imported
        self.plan = nil
        await records.reload()
        if !failures.isEmpty {
            let shown = failures.prefix(3).joined(separator: "\n")
            let extra = failures.count > 3 ? "\nand \(failures.count - 3) more." : ""
            errorMessage = "Imported \(imported). \(failures.count) row(s) could not be saved:\n\(shown)\(extra)"
        }
    }
}
