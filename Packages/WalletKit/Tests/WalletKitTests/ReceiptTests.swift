import Foundation
import Testing
import WalletData
import WalletDomain
@testable import WalletFeature

struct ReceiptTextReaderTests {
    /// A line naming the total wins over larger numbers elsewhere on the receipt.
    @Test func aLineNamingTheTotalIsPreferred() {
        let lines = ["CORNER SHOP", "Item A 3.50", "Item B 12.00", "Subtotal 15.50",
                     "VAT 3.10", "TOTAL 18.60", "Card 18.60"]
        #expect(ReceiptTextReader.amount(in: lines) == Decimal(string: "18.60"))
    }

    @Test func subtotalsTaxesAndChangeAreNeverTakenAsTheTotal() {
        let lines = ["Subtotal 99.99", "Tax 8.00", "Total 20.00", "Change 80.00"]
        #expect(ReceiptTextReader.amount(in: lines) == Decimal(string: "20.00"))
    }

    /// With no keyword anywhere, the largest amount is nearly always the total.
    @Test func theLargestAmountIsUsedWhenNoLineNamesATotal() {
        let lines = ["Coffee 3.20", "Cake 4.80", "8.00"]
        #expect(ReceiptTextReader.amount(in: lines) == Decimal(string: "8.00"))
    }

    @Test func groupedAndCommaDecimalAmountsAreUnderstood() {
        #expect(ReceiptTextReader.amount(in: ["Total 1,234.56"]) == Decimal(string: "1234.56"))
        #expect(ReceiptTextReader.amount(in: ["Total 1.234,56"]) == Decimal(string: "1234.56"))
        #expect(ReceiptTextReader.amount(in: ["Total 12,50"]) == Decimal(string: "12.50"))
    }

    @Test func textWithoutAnAmountYieldsNothing() {
        #expect(ReceiptTextReader.amount(in: ["THANK YOU", "CALL AGAIN"]) == nil)
        #expect(ReceiptTextReader.interpret(lines: []).isEmpty)
    }

    /// Quantities and phone numbers must not be mistaken for money.
    @Test func integersWithoutDecimalsAreNotAmounts() {
        #expect(ReceiptTextReader.amount(in: ["Qty 2", "Tel 5551234"]) == nil)
    }

    @Test func aDateIsReadFromCommonReceiptFormats() {
        let now = Date(timeIntervalSince1970: 1_705_320_000) // 2024-01-15
        #expect(ReceiptTextReader.date(in: ["Date: 2024-01-10"], now: now) != nil)
        #expect(ReceiptTextReader.date(in: ["10/01/2024 14:22"], now: now) != nil)
        #expect(ReceiptTextReader.date(in: ["No date here"], now: now) == nil)
    }

    /// A receipt cannot be dated in the future, so such a match is rejected.
    @Test func futureDatesAreIgnored() {
        let now = Date(timeIntervalSince1970: 1_705_320_000)
        #expect(ReceiptTextReader.date(in: ["2030-05-01"], now: now) == nil)
    }
}

@MainActor
struct ReceiptStorageTests {
    private func makeRepository() async throws -> SwiftDataWalletRepository {
        try await SwiftDataWalletRepository.make(configuration: .inMemory)
    }

    private func makeRecord(_ repository: SwiftDataWalletRepository) async throws -> UUID {
        let accounts = AccountUseCases(repository: repository)
        try await accounts.create(name: "Cash", type: .cash, currencyCode: "USD")
        let account = try #require(try await accounts.load().first)
        let categories = try await CategoryUseCases(repository: repository).load()
        let category = try #require(categories.first { $0.parentID == nil })

        var draft = RecordDraft()
        draft.accountID = account.id
        draft.categoryID = category.id
        draft.amount = 10
        let id = UUID()
        try await RecordUseCases(repository: repository).create(id: id, draft: draft)
        return id
    }

    private func page(_ byte: UInt8, size: Int = 32) -> Data { Data(repeating: byte, count: size) }

    @Test func pagesAreStoredInOrderAndAppendAfterExistingOnes() async throws {
        let repository = try await makeRepository()
        let recordID = try await makeRecord(repository)
        let useCases = ReceiptUseCases(repository: repository)

        try await useCases.append(pages: [page(1), page(2)], to: recordID)
        try await useCases.append(pages: [page(3)], to: recordID)

        let stored = try await useCases.load(recordID: recordID)
        #expect(stored.map(\.pageIndex) == [0, 1, 2])
        #expect(stored.map(\.imageData) == [page(1), page(2), page(3)])
        #expect(stored.allSatisfy { $0.recordID == recordID })
    }

    @Test func pageCountsAreReportedPerRecord() async throws {
        let repository = try await makeRepository()
        let first = try await makeRecord(repository)
        let useCases = ReceiptUseCases(repository: repository)
        try await useCases.append(pages: [page(1), page(2)], to: first)

        let counts = try await useCases.pageCounts()
        #expect(counts[first] == 2)
    }

    @Test func oversizedAndEmptyPagesAreRejectedWithoutStoringAnything() async throws {
        let repository = try await makeRepository()
        let recordID = try await makeRecord(repository)
        let useCases = ReceiptUseCases(repository: repository)

        await #expect(throws: ReceiptError.emptyImage) {
            try await useCases.append(pages: [page(1), Data()], to: recordID)
        }
        await #expect(throws: ReceiptError.tooLarge) {
            try await useCases.append(pages: [page(1, size: ReceiptUseCases.maximumPageBytes + 1)],
                                      to: recordID)
        }
        // The whole batch is refused, so nothing partial is left behind.
        #expect(try await useCases.load(recordID: recordID).isEmpty)
    }

    @Test func thePageLimitIsEnforced() async throws {
        let repository = try await makeRepository()
        let recordID = try await makeRecord(repository)
        let useCases = ReceiptUseCases(repository: repository)

        let full = (0..<ReceiptUseCases.pageLimit).map { page(UInt8($0)) }
        try await useCases.append(pages: full, to: recordID)

        await #expect(throws: ReceiptError.tooManyPages(ReceiptUseCases.pageLimit)) {
            try await useCases.append(pages: [page(99)], to: recordID)
        }
        #expect(try await useCases.load(recordID: recordID).count == ReceiptUseCases.pageLimit)
    }

    @Test func deletingAPageLeavesTheRest() async throws {
        let repository = try await makeRepository()
        let recordID = try await makeRecord(repository)
        let useCases = ReceiptUseCases(repository: repository)
        try await useCases.append(pages: [page(1), page(2), page(3)], to: recordID)

        let stored = try await useCases.load(recordID: recordID)
        try await useCases.delete(id: stored[1].id)

        let remaining = try await useCases.load(recordID: recordID)
        #expect(remaining.map(\.imageData) == [page(1), page(3)])
    }

    /// Deleting a record must not leave its scanned pages orphaned in the store.
    @Test func deletingARecordRemovesItsPages() async throws {
        let repository = try await makeRepository()
        let recordID = try await makeRecord(repository)
        let useCases = ReceiptUseCases(repository: repository)
        try await useCases.append(pages: [page(1), page(2)], to: recordID)

        try await RecordUseCases(repository: repository).delete(id: recordID)

        #expect(try await useCases.load(recordID: recordID).isEmpty)
        #expect(try await useCases.pageCounts().isEmpty)
    }

    @Test func resettingTheWalletRemovesEveryPage() async throws {
        let repository = try await makeRepository()
        let recordID = try await makeRecord(repository)
        let useCases = ReceiptUseCases(repository: repository)
        try await useCases.append(pages: [page(1)], to: recordID)

        try await ResetWalletUseCase(repository: repository).execute()
        #expect(try await useCases.pageCounts().isEmpty)
    }
}
