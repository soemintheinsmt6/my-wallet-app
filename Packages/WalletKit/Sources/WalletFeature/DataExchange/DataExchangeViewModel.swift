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
    /// The file has no Account column (bank statements rarely do), so the person picks one first.
    @Published public private(set) var needsAccountChoice = false
    @Published public private(set) var importOptions = RecordCSVImportOptions()
    /// The file states direction by Type rather than by sign, so flipping signs would do nothing.
    @Published public private(set) var canReverseSigns = false
    /// Categories for income and expense rows the file leaves uncategorised, as bank statements do.
    @Published public private(set) var fallbackCategoryIDs: [RecordKind: UUID] = [:]
    /// Whether uncategorised rows take the category last used for their payee before the fallback.
    @Published public private(set) var usesLearnedCategories = true
    /// Rows matched to an existing record that the person chose to import anyway.
    @Published public private(set) var unmatchedRowIndices: Set<Int> = []
    /// Whether matched records take the bank's amount, so a tip or fee reaches the balance.
    @Published public private(set) var updatesMatchedAmounts = true
    /// Records whose amount the last import changed to the bank's.
    @Published public private(set) var updatedCount = 0
    /// Matched split records left at their amount, since their shares must add up to it.
    @Published public private(set) var keptSplitCount = 0

    /// The parsed file, kept so a chosen account or flipped signs re-plan without rereading it.
    private var pendingTable: [[String]]?
    private var pendingMapping: [RecordCSVColumn: Int] = [:]

    private let records: RecordsViewModel
    private let recordUseCases: RecordUseCases
    private let tagUseCases: TagUseCases
    /// Read before changing a matched record's amount: a split's shares must add up to it.
    private let splitUseCases: SplitUseCases?

    public init(records: RecordsViewModel, recordUseCases: RecordUseCases, tagUseCases: TagUseCases,
                splitUseCases: SplitUseCases? = nil) {
        self.records = records
        self.recordUseCases = recordUseCases
        self.tagUseCases = tagUseCases
        self.splitUseCases = splitUseCases
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
        do {
            // Files handed over by the document picker live outside the app's sandbox.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            prepareImport(text: decodeText(try Data(contentsOf: url)))
        } catch {
            cancelImport()
            errorMessage = error.localizedDescription
        }
    }

    /// Parses CSV text and either plans it or asks for an account when the file names none.
    public func prepareImport(text: String) {
        cancelImport()
        importedCount = 0
        updatedCount = 0
        keptSplitCount = 0
        do {
            let table = try CSV.parse(text)
            guard let header = table.first else { throw CSVError.empty }
            let mapping = RecordCSV.mapping(header: header)
            // Report every other missing column now rather than after the account is chosen.
            let missing = RecordCSV.missingColumns(in: mapping).filter { $0 != .account }
            guard missing.isEmpty else { throw RecordCSVError.missingColumns(missing) }

            pendingTable = table
            pendingMapping = mapping
            canReverseSigns = mapping[.type] == nil || mapping[.debit] != nil || mapping[.credit] != nil
            // Money in is almost always income, so start uncategorised income in the starter
            // Income category; spending varies too much to guess, so the person picks it.
            if let income = records.categories.first(where: {
                $0.parentID == nil && $0.name.caseInsensitiveCompare("Income") == .orderedSame
            }) {
                fallbackCategoryIDs[.income] = income.id
            }
            if mapping[.account] == nil {
                needsAccountChoice = true
            } else {
                replan()
            }
        } catch {
            cancelImport()
            errorMessage = error.localizedDescription
        }
    }

    /// Accounts a statement without an Account column can be imported into.
    public var accountNames: [String] { records.accounts.map(\.name) }

    public func chooseImportAccount(_ name: String) {
        needsAccountChoice = false
        importOptions.defaultAccountName = name
        replan()
    }

    public func setReversesSigns(_ reverses: Bool) {
        guard importOptions.reversesSigns != reverses else { return }
        importOptions.reversesSigns = reverses
        replan()
    }

    /// Overrides a match the person judges wrong, such as a second identical purchase they never
    /// entered. Cancelling the import clears these choices.
    public func importAnyway(_ entry: ImportPlan.Entry) {
        guard entry.matchedRecordDate != nil, unmatchedRowIndices.insert(entry.rowIndex).inserted else { return }
        replan()
    }

    public func setUpdatesMatchedAmounts(_ updates: Bool) {
        updatesMatchedAmounts = updates
    }

    /// The record changes Import would make, given the toggle.
    public var pendingAmountUpdates: [ImportPlan.AmountUpdate] {
        updatesMatchedAmounts ? plan?.amountUpdates ?? [] : []
    }

    public func setFallbackCategory(_ id: UUID?, for kind: RecordKind) {
        guard fallbackCategoryIDs[kind] != id else { return }
        fallbackCategoryIDs[kind] = id
        replan()
    }

    public func setUsesLearnedCategories(_ uses: Bool) {
        guard usesLearnedCategories != uses else { return }
        usesLearnedCategories = uses
        replan()
    }

    /// Every category and subcategory by its full path, for choosing a fallback.
    public var categoryChoices: [(id: UUID, path: String)] {
        let byID = Dictionary(records.categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return records.categories
            .map { (id: $0.id, path: RecordCSV.path(for: $0.id, in: byID)) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func replan() {
        guard let table = pendingTable else { return }
        do {
            let rows = try RecordCSV.rows(from: table, mapping: pendingMapping, options: importOptions)
            plan = ImportPlanner.plan(rows: rows, accounts: records.accounts,
                                      categories: records.categories, tags: records.tags,
                                      existing: records.records, fallbackCategoryIDs: fallbackCategoryIDs,
                                      categorizer: usesLearnedCategories ? records.payeeCategorizer : nil,
                                      unmatchedRowIndices: unmatchedRowIndices)
            errorMessage = nil
        } catch {
            cancelImport()
            errorMessage = error.localizedDescription
        }
    }

    /// The payee for a bank row (its description), else the category it will be saved under.
    public func previewTitle(for entry: ImportPlan.Entry) -> String {
        if entry.row.isAdjustment { return RecordDraft.adjustmentTitle }
        if titlesByPayee(entry) { return entry.row.payee }
        if !entry.row.categoryPath.isEmpty, !entry.isUncategorized, !entry.hasLearnedCategory {
            return entry.row.categoryPath
        }
        return categoryPath(for: entry) ?? entry.row.kind.title
    }

    /// The category a row titled by its payee will be saved under, so the preview shows both.
    public func previewCategory(for entry: ImportPlan.Entry) -> String? {
        titlesByPayee(entry) ? categoryPath(for: entry) : nil
    }

    /// A row the file gave no category for is better known by its payee.
    private func titlesByPayee(_ entry: ImportPlan.Entry) -> Bool {
        !entry.row.isAdjustment && (entry.isUncategorized || entry.hasLearnedCategory) && !entry.row.payee.isEmpty
    }

    private func categoryPath(for entry: ImportPlan.Entry) -> String? {
        categoryChoices.first { $0.id == entry.categoryID }?.path
    }

    /// The row's own currency, else its account's, so a statement without a Currency column
    /// previews in the account's currency rather than a guess.
    public func currencyCode(for entry: ImportPlan.Entry) -> String {
        if !entry.row.currencyCode.isEmpty { return entry.row.currencyCode }
        return records.accounts.first { $0.id == entry.accountID }?.currencyCode ?? "USD"
    }

    /// Files exported from other tools are not always UTF-8. Latin-1 maps every byte to a character,
    /// so it accepts whatever UTF-8 rejected; the empty fallback is never reached in practice.
    private func decodeText(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    public func cancelImport() {
        plan = nil
        errorMessage = nil
        needsAccountChoice = false
        pendingTable = nil
        pendingMapping = [:]
        importOptions = RecordCSVImportOptions()
        canReverseSigns = false
        fallbackCategoryIDs = [:]
        usesLearnedCategories = true
        unmatchedRowIndices = []
        updatesMatchedAmounts = true
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
            draft.isAdjustment = entry.row.isAdjustment
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

        let updates = await applyAmountUpdates(pendingAmountUpdates)

        cancelImport()
        importedCount = imported
        updatedCount = updates.updated
        keptSplitCount = updates.keptSplits
        await records.reload()
        var messages: [String] = []
        if !failures.isEmpty {
            let shown = failures.prefix(3).joined(separator: "\n")
            let extra = failures.count > 3 ? "\nand \(failures.count - 3) more." : ""
            messages.append("Imported \(imported). \(failures.count) row(s) could not be saved:\n\(shown)\(extra)")
        }
        if !updates.failures.isEmpty {
            messages.append("\(updates.failures.count) record(s) kept their amount:\n"
                            + updates.failures.prefix(3).joined(separator: "\n"))
        }
        errorMessage = messages.isEmpty ? nil : messages.joined(separator: "\n\n")
    }

    /// Brings matched records to the bank's amounts. A transfer can have both sides changed, so
    /// changes are grouped per record and each record is saved once.
    private func applyAmountUpdates(_ updates: [ImportPlan.AmountUpdate]) async
        -> (updated: Int, keptSplits: Int, failures: [String]) {
        guard !updates.isEmpty else { return (0, 0, []) }
        let splitRecordIDs: Set<UUID>
        do {
            splitRecordIDs = Set(try await splitUseCases?.load().map(\.recordID) ?? [])
        } catch {
            return (0, 0, ["Splits could not be read, so no amounts were changed: \(error.localizedDescription)"])
        }
        let recordsByID = Dictionary(records.records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var updated = 0
        var keptSplits = 0
        var failures: [String] = []
        let grouped = Dictionary(grouping: updates, by: \.recordID)
        for (offset, (recordID, changes)) in grouped.enumerated() {
            progress = "Updating \(offset + 1) of \(grouped.count)…"
            // A split's shares must add up to the record's amount, so changing it alone would break the split.
            guard !splitRecordIDs.contains(recordID) else { keptSplits += 1; continue }
            guard let record = recordsByID[recordID] else {
                failures.append("A matched record no longer exists.")
                continue
            }
            var draft = record.draft
            changes.forEach { $0.apply(to: &draft) }
            do {
                // Loaded records carry no photo bytes and saving writes the photo, so without this
                // an amount update would erase the receipt.
                if record.hasPhoto {
                    guard let photo = try await recordUseCases.photo(id: recordID) else {
                        throw RecordValidationError.invalidPhoto
                    }
                    draft.photoData = photo
                }
                try await recordUseCases.update(id: recordID, draft: draft)
                updated += 1
            } catch {
                failures.append("\(record.draft.date.formatted(date: .abbreviated, time: .shortened)): \(error.localizedDescription)")
            }
        }
        return (updated, keptSplits, failures)
    }
}
