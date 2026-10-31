import Foundation
import Testing
import WalletDomain

struct CSVTests {
    @Test func plainValuesAreWrittenUnquoted() {
        #expect(CSV.encode(rows: [["a", "b"], ["1", "2"]]) == "a,b\r\n1,2")
    }

    @Test func valuesNeedingQuotesRoundTrip() throws {
        let rows = [["Note", "Payee"],
                    ["Lunch, with tax", "O\"Brien"],
                    ["Line one\nline two", "Trailing space "],
                    ["", "plain"]]
        let encoded = CSV.encode(rows: rows)
        #expect(encoded.contains("\"Lunch, with tax\""))
        #expect(encoded.contains("\"O\"\"Brien\""))
        #expect(try CSV.parse(encoded) == rows)
    }

    @Test func parsingAcceptsBothLineEndingsBOMAndATrailingNewline() throws {
        #expect(try CSV.parse("a,b\r\n1,2\r\n") == [["a", "b"], ["1", "2"]])
        #expect(try CSV.parse("a,b\n1,2\n") == [["a", "b"], ["1", "2"]])
        #expect(try CSV.parse("\u{FEFF}a,b\n1,2") == [["a", "b"], ["1", "2"]])
        // Blank lines are skipped rather than becoming empty records.
        #expect(try CSV.parse("a,b\n\n1,2\n\n") == [["a", "b"], ["1", "2"]])
    }

    @Test func emptyTrailingFieldsArePreserved() throws {
        #expect(try CSV.parse("a,b,c\n1,,3") == [["a", "b", "c"], ["1", "", "3"]])
        #expect(try CSV.parse("a,b\n1,") == [["a", "b"], ["1", ""]])
    }

    @Test func anUnterminatedQuoteIsReported() {
        #expect(throws: CSVError.unterminatedQuote(line: 2)) {
            try CSV.parse("a,b\n\"oops,2")
        }
    }

    @Test func anEmptyFileIsReported() {
        #expect(throws: CSVError.empty) { try CSV.parse("") }
        #expect(throws: CSVError.empty) { try CSV.parse("\n\n") }
    }
}

struct RecordCSVTests {
    private let now = Date(timeIntervalSince1970: 1_704_110_400)

    private func account(_ name: String, currency: String = "USD") -> Account {
        Account(name: name, type: .cash, currencyCode: currency)
    }

    @Test func exportedRecordsReimportUnchanged() throws {
        let cash = account("Cash")
        let savings = account("Savings")
        let root = WalletCategory(name: "Food & Drinks")
        let child = WalletCategory(parentID: root.id, name: "Groceries")
        let tag = WalletTag(name: "Work")

        var draft = RecordDraft()
        draft.kind = .expense
        draft.accountID = cash.id
        draft.amount = Decimal(string: "12.34")!
        draft.categoryID = child.id
        draft.date = now
        draft.tagIDs = [tag.id]
        draft.payee = "Corner Shop, Ltd"
        draft.note = "Weekly \"big\" shop\nsecond line"
        draft.paymentType = .creditCard
        let expense = WalletRecord(id: UUID(), draft: draft, currencyCode: "USD")

        var transfer = RecordDraft()
        transfer.kind = .transfer
        transfer.accountID = cash.id
        transfer.destinationAccountID = savings.id
        transfer.amount = 500
        transfer.date = now.addingTimeInterval(3600)
        let move = WalletRecord(id: UUID(), draft: transfer, currencyCode: "USD")

        let text = RecordCSV.export(records: [expense, move], accounts: [cash, savings],
                                    categories: [root, child], tags: [tag])
        let table = try CSV.parse(text)
        let rows = try RecordCSV.rows(from: table, mapping: RecordCSV.mapping(header: table[0]))

        #expect(rows.count == 2)
        #expect(rows[0].amount == Decimal(string: "12.34")!)
        #expect(rows[0].kind == .expense)
        #expect(rows[0].accountName == "Cash")
        #expect(rows[0].categoryPath == "Food & Drinks / Groceries")
        #expect(rows[0].labelNames == ["Work"])
        #expect(rows[0].payee == "Corner Shop, Ltd")
        #expect(rows[0].note == "Weekly \"big\" shop\nsecond line")
        #expect(rows[0].paymentType == .creditCard)
        #expect(Int(rows[0].date.timeIntervalSince1970) == Int(now.timeIntervalSince1970))
        #expect(rows[1].kind == .transfer)
        #expect(rows[1].destinationAccountName == "Savings")
    }

    @Test func headerMappingIgnoresCaseOrderAndUnknownColumns() throws {
        let table = [["Memo", "type", "  AMOUNT ", "Account", "Date"],
                     ["ignored", "expense", "5", "Cash", "2024-01-01"]]
        let mapping = RecordCSV.mapping(header: table[0])
        let rows = try RecordCSV.rows(from: table, mapping: mapping)

        #expect(rows.count == 1)
        #expect(rows[0].amount == 5)
        #expect(rows[0].accountName == "Cash")
    }

    @Test func missingRequiredColumnsAreReported() {
        let table = [["Date", "Amount"], ["2024-01-01", "5"]]
        #expect(throws: RecordCSVError.missingColumns([.type, .account])) {
            try RecordCSV.rows(from: table, mapping: RecordCSV.mapping(header: table[0]))
        }
    }

    /// The reported row number must match what the user sees in a spreadsheet.
    @Test func badValuesReportTheSpreadsheetRowNumber() {
        let header = ["Date", "Type", "Amount", "Account"]
        func table(_ row: [String]) -> [[String]] { [header, ["2024-01-01", "expense", "1", "Cash"], row] }

        #expect(throws: RecordCSVError.invalidDate(row: 3, value: "not-a-date")) {
            try RecordCSV.rows(from: table(["not-a-date", "expense", "1", "Cash"]),
                               mapping: RecordCSV.mapping(header: header))
        }
        #expect(throws: RecordCSVError.invalidType(row: 3, value: "refund")) {
            try RecordCSV.rows(from: table(["2024-01-01", "refund", "1", "Cash"]),
                               mapping: RecordCSV.mapping(header: header))
        }
        #expect(throws: RecordCSVError.invalidAmount(row: 3, value: "-5")) {
            try RecordCSV.rows(from: table(["2024-01-01", "expense", "-5", "Cash"]),
                               mapping: RecordCSV.mapping(header: header))
        }
        #expect(throws: RecordCSVError.missingAccount(row: 3)) {
            try RecordCSV.rows(from: table(["2024-01-01", "expense", "1", ""]),
                               mapping: RecordCSV.mapping(header: header))
        }
    }

    /// Raw values are camelCase, so a naive lowercase comparison silently loses the type.
    @Test func paymentTypesParseRegardlessOfCase() {
        #expect(RecordCSV.paymentType(from: "creditCard") == .creditCard)
        #expect(RecordCSV.paymentType(from: "CREDITCARD") == .creditCard)
        #expect(RecordCSV.paymentType(from: "bankTransfer") == .bankTransfer)
        #expect(RecordCSV.paymentType(from: "") == .unspecified)
        #expect(RecordCSV.paymentType(from: "cheque by post") == .unspecified)
    }

    @Test func amountsParseWithEitherDecimalSeparatorAndGrouping() {
        #expect(RecordCSV.decimal(from: "12.34") == Decimal(string: "12.34"))
        #expect(RecordCSV.decimal(from: "12,34") == Decimal(string: "12.34"))
        #expect(RecordCSV.decimal(from: "1,234.56") == Decimal(string: "1234.56"))
        #expect(RecordCSV.decimal(from: "1.234,56") == Decimal(string: "1234.56"))
        #expect(RecordCSV.decimal(from: "$1,200") == Decimal(string: "1200"))
        #expect(RecordCSV.decimal(from: "") == nil)
    }

    @Test func datesParseFromCommonSpreadsheetForms() {
        #expect(RecordCSV.date(from: "2024-01-01T12:00:00Z") != nil)
        #expect(RecordCSV.date(from: "2024-01-01 12:00") != nil)
        #expect(RecordCSV.date(from: "2024-01-01") != nil)
        #expect(RecordCSV.date(from: "01/02/2024") != nil)
        #expect(RecordCSV.date(from: "yesterday") == nil)
    }

    /// Exact decimals must survive; a double round trip would corrupt them.
    @Test func amountsAreWrittenExactly() {
        #expect(RecordCSV.string(from: Decimal(string: "0.1")!) == "0.1")
        #expect(RecordCSV.string(from: Decimal(string: "12345678.87654321")!) == "12345678.87654321")
    }
}

struct WalletArchiveTests {
    @Test func archiveRoundTripsAndDropsPhotoBytes() throws {
        let cash = Account(name: "Cash", type: .cash)
        let category = WalletCategory(name: "Food")
        let tag = WalletTag(name: "Work")
        var draft = RecordDraft()
        draft.accountID = cash.id
        draft.amount = Decimal(string: "9.99")!
        draft.categoryID = category.id
        draft.photoData = Data(repeating: 0xAB, count: 1024)
        let record = WalletRecord(id: UUID(), draft: draft, currencyCode: "USD")

        let data = try WalletArchive.encode(
            WalletArchive(accounts: [cash], categories: [category], tags: [tag], records: [record]))
        let restored = try WalletArchive.decode(data)

        #expect(restored.version == WalletArchive.currentVersion)
        #expect(restored.accounts.first?.id == cash.id)
        #expect(restored.categories.first?.name == "Food")
        #expect(restored.tags.first?.name == "Work")
        #expect(restored.records.first?.id == record.id)
        #expect(restored.records.first?.draft.amount == Decimal(string: "9.99")!)
        #expect(restored.records.first?.draft.photoData == nil)
    }

    @Test func accountIconsAreBackedUpAndOlderBackupsWithoutThemStillDecode() throws {
        let card = Account(name: "Card", type: .creditCard, settings: AccountSettings(symbol: "star"))
        let restored = try WalletArchive.decode(
            WalletArchive.encode(WalletArchive(accounts: [card], categories: [], tags: [], records: [])))
        #expect(restored.accounts.first?.symbol == "star")

        // A backup written before account icons existed has no "symbol" key at all.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(try JSONSerialization.jsonObject(
            with: encoder.encode(WalletArchive(accounts: [card], categories: [], tags: [], records: []))) as? [String: Any])
        var accounts = try #require(object["accounts"] as? [[String: Any]])
        accounts[0].removeValue(forKey: "symbol")
        object["accounts"] = accounts
        let older = try WalletArchive.decode(JSONSerialization.data(withJSONObject: object))
        #expect(older.accounts.first?.symbol == nil)
        #expect(older.accounts.first?.id == card.id)
    }

    @Test func aNewerArchiveIsRefusedRatherThanMisread() throws {
        var archive = WalletArchive(accounts: [], categories: [], tags: [], records: [])
        archive.version = WalletArchive.currentVersion + 1
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)
        #expect(throws: ArchiveError.unsupportedVersion(WalletArchive.currentVersion + 1)) {
            try WalletArchive.decode(data)
        }
    }
}

struct ImportPlannerTests {
    private let now = Date(timeIntervalSince1970: 1_704_110_400)

    private func row(amount: Decimal = 10, kind: RecordKind = .expense, account: String = "Cash",
                     destination: String = "", category: String = "", labels: [String] = [],
                     offset: TimeInterval = 0) -> RecordCSVRow {
        RecordCSVRow(date: now.addingTimeInterval(offset), kind: kind, amount: amount,
                     accountName: account, destinationAccountName: destination,
                     categoryPath: category, labelNames: labels)
    }

    private func existingRecord(amount: Decimal, account: Account, kind: RecordKind = .expense,
                                offset: TimeInterval = 0) -> WalletRecord {
        var draft = RecordDraft()
        draft.kind = kind
        draft.accountID = account.id
        draft.amount = amount
        draft.date = now.addingTimeInterval(offset)
        return WalletRecord(id: UUID(), draft: draft, currencyCode: "USD")
    }

    @Test func rowsMatchAccountsCategoriesAndLabelsByName() {
        let cash = Account(name: "Cash", type: .cash)
        let root = WalletCategory(name: "Food & Drinks")
        let child = WalletCategory(parentID: root.id, name: "Groceries")
        let tag = WalletTag(name: "Work")

        let plan = ImportPlanner.plan(
            rows: [row(category: "food & drinks / groceries", labels: ["work", "Travel"])],
            accounts: [cash], categories: [root, child], tags: [tag], existing: [])

        let entry = plan.entries[0]
        #expect(entry.isImportable)
        #expect(entry.accountID == cash.id)
        #expect(entry.categoryID == child.id)
        #expect(entry.tagIDs == [tag.id])
        #expect(entry.newLabelNames == ["Travel"])
        #expect(plan.labelsToCreate == ["Travel"])
    }

    @Test func unmatchedAccountsAndBadTransfersAreFlagged() {
        let cash = Account(name: "Cash", type: .cash)
        let plan = ImportPlanner.plan(
            rows: [row(account: "Nowhere"),
                   row(kind: .transfer, offset: 1),
                   row(kind: .transfer, destination: "Missing", offset: 2),
                   row(kind: .transfer, destination: "Cash", offset: 3)],
            accounts: [cash], categories: [], tags: [], existing: [])

        #expect(plan.entries[0].issue == .unknownAccount("Nowhere"))
        #expect(plan.entries[1].issue == .transferNeedsDestination)
        #expect(plan.entries[2].issue == .unknownDestinationAccount("Missing"))
        #expect(plan.entries[3].issue == .transferToSameAccount)
        #expect(plan.importable.isEmpty)
        #expect(plan.problems.count == 4)
    }

    @Test func reimportingAnExportIsDetectedAsDuplicates() {
        let cash = Account(name: "Cash", type: .cash)
        let existing = existingRecord(amount: 10, account: cash)
        let plan = ImportPlanner.plan(rows: [row()], accounts: [cash], categories: [], tags: [],
                                      existing: [existing])

        #expect(plan.duplicates.count == 1)
        #expect(plan.importable.isEmpty)
    }

    /// A file containing the same row twice must not import it twice.
    @Test func duplicatesWithinTheFileItselfAreCaught() {
        let cash = Account(name: "Cash", type: .cash)
        let plan = ImportPlanner.plan(rows: [row(), row()], accounts: [cash], categories: [],
                                      tags: [], existing: [])

        #expect(plan.importable.count == 1)
        #expect(plan.duplicates.count == 1)
    }

    @Test func recordsDifferingInAnyFingerprintFieldAreNotDuplicates() {
        let cash = Account(name: "Cash", type: .cash)
        let existing = existingRecord(amount: 10, account: cash)
        let plan = ImportPlanner.plan(
            rows: [row(amount: 11), row(kind: .income, offset: 1), row(offset: 60)],
            accounts: [cash], categories: [], tags: [], existing: [existing])

        #expect(plan.importable.count == 3)
        #expect(plan.duplicates.isEmpty)
    }

    @Test func everyRowLandsInExactlyOneBucket() {
        let cash = Account(name: "Cash", type: .cash)
        let existing = existingRecord(amount: 10, account: cash)
        let plan = ImportPlanner.plan(
            rows: [row(), row(amount: 25, offset: 1), row(account: "Nowhere", offset: 2)],
            accounts: [cash], categories: [], tags: [], existing: [existing])

        #expect(plan.entries.count == 3)
        #expect(plan.importable.count + plan.duplicates.count + plan.problems.count == plan.entries.count)
    }
}
