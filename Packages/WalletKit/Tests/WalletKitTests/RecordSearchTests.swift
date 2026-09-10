import Foundation
import Testing
import WalletDomain
@testable import WalletFeature

struct RecordSearchTests {
    private let start = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 UTC

    private func record(amount: Decimal = 10, day: Int = 0, kind: RecordKind = .expense,
                        account: UUID? = UUID(), destination: UUID? = nil, category: UUID? = nil,
                        tags: Set<UUID> = [], note: String = "", payee: String = "",
                        payment: PaymentType = .unspecified, received: Decimal? = nil) -> WalletRecord {
        var draft = RecordDraft()
        draft.kind = kind
        draft.accountID = account
        draft.destinationAccountID = destination
        draft.amount = amount
        draft.receivedAmount = received
        draft.categoryID = category
        draft.date = start.addingTimeInterval(Double(day) * 86400)
        draft.tagIDs = tags
        draft.note = note
        draft.payee = payee
        draft.paymentType = payment
        return WalletRecord(id: UUID(), draft: draft, currencyCode: "USD")
    }

    @Test func textMatchesNotePayeeAmountCategoryAndLabelNames() {
        let root = WalletCategory(name: "Food")
        let child = WalletCategory(parentID: root.id, name: "Groceries")
        let tag = WalletTag(name: "Reimbursable")
        let byNote = record(note: "Weekly coffee beans")
        let byPayee = record(payee: "Coffee House")
        let byAmount = record(amount: Decimal(string: "12.50")!)
        let byCategory = record(category: child.id)
        let byLabel = record(tags: [tag.id])
        let unrelated = record(note: "Bus ticket")
        let records = [byNote, byPayee, byAmount, byCategory, byLabel, unrelated]

        func ids(_ text: String) -> Set<UUID> {
            Set(RecordSearch.run(records: records, categories: [root, child], tags: [tag],
                                 query: RecordQuery(text: text)).map(\.id))
        }
        #expect(ids("coffee") == [byNote.id, byPayee.id])
        #expect(ids("12") == [byAmount.id])
        #expect(ids("12.50") == [byAmount.id])
        #expect(ids("groceries") == [byCategory.id])
        #expect(ids("food") == [byCategory.id]) // parent name of the assigned subcategory
        #expect(ids("reimbursable") == [byLabel.id])
        #expect(ids("nothing here").isEmpty)
    }

    @Test func everyTermMustMatchAndComparisonIgnoresCaseAndDiacritics() {
        let category = WalletCategory(name: "Café")
        let both = record(category: category.id, payee: "Blue Bottle")
        let onlyPayee = record(payee: "Blue Bottle")
        let records = [both, onlyPayee]
        let matches = RecordSearch.run(records: records, categories: [category],
                                       query: RecordQuery(text: "cafe BLUE"))
        #expect(matches.map(\.id) == [both.id])
        #expect(RecordSearch.run(records: records, categories: [category], query: RecordQuery(text: "CAFE")).count == 1)
    }

    @Test func relevanceRanksPayeeAboveCategoryAboveNoteAndBreaksTiesByNewest() {
        let category = WalletCategory(name: "Market")
        let payeeExact = record(day: 0, payee: "Market")
        let categoryMatch = record(day: 1, category: category.id)
        let notePartial = record(day: 2, note: "Supermarket receipt")
        let olderPayeeExact = record(day: -1, payee: "Market")
        let ranked = RecordSearch.run(records: [notePartial, categoryMatch, olderPayeeExact, payeeExact],
                                      categories: [category], query: RecordQuery(text: "market"))
        #expect(ranked.map(\.id) == [payeeExact.id, olderPayeeExact.id, categoryMatch.id, notePartial.id])
        #expect(ranked[0].score > ranked[2].score)
    }

    @Test func filtersIntersectAcrossGroupsAndUnionInsideAGroup() {
        let cash = UUID()
        let bank = UUID()
        let root = WalletCategory(name: "Home")
        let child = WalletCategory(parentID: root.id, name: "Rent")
        let other = WalletCategory(name: "Travel")
        let label = UUID()
        let target = record(amount: 100, kind: .expense, account: cash, category: child.id,
                            tags: [label], payment: .cash)
        let wrongKind = record(amount: 100, kind: .income, account: cash, category: child.id, tags: [label], payment: .cash)
        let wrongAccount = record(amount: 100, account: bank, category: child.id, tags: [label], payment: .cash)
        let wrongCategory = record(amount: 100, account: cash, category: other.id, tags: [label], payment: .cash)
        let uncategorized = record(amount: 100, account: cash, category: nil, tags: [label], payment: .cash)
        let wrongLabel = record(amount: 100, account: cash, category: child.id, tags: [], payment: .cash)
        let wrongPayment = record(amount: 100, account: cash, category: child.id, tags: [label], payment: .creditCard)
        let rootCategory = record(amount: 100, account: cash, category: root.id, tags: [label], payment: .cash)
        let records = [target, wrongKind, wrongAccount, wrongCategory, uncategorized, wrongLabel, wrongPayment, rootCategory]

        let query = RecordQuery(kinds: [.expense], accountIDs: [cash], categoryIDs: [root.id],
                                tagIDs: [label, UUID()], paymentTypes: [.cash, .cheque])
        let matches = RecordSearch.run(records: records, categories: [root, child, other], query: query)
        #expect(Set(matches.map(\.id)) == [target.id, rootCategory.id]) // a root selection includes its children
        #expect(query.activeFilterCount == 5)
    }

    @Test func accountFilterMatchesEitherSideOfATransfer() {
        let cash = UUID()
        let savings = UUID()
        let incoming = record(kind: .transfer, account: UUID(), destination: savings, received: 5)
        let outgoing = record(kind: .transfer, account: savings, destination: UUID(), received: 5)
        let unrelated = record(kind: .transfer, account: cash, destination: UUID(), received: 5)
        let matches = RecordSearch.run(records: [incoming, outgoing, unrelated],
                                       query: RecordQuery(accountIDs: [savings]))
        #expect(Set(matches.map(\.id)) == [incoming.id, outgoing.id])
    }

    @Test func dateRangeIncludesTheStartAndExcludesTheEndWhileAmountBoundsAreInclusive() {
        let before = record(amount: 5, day: -1)
        let onStart = record(amount: 10, day: 0)
        let inside = record(amount: 50, day: 1)
        let onEnd = record(amount: 100, day: 2)
        let records = [before, onStart, inside, onEnd]
        let dated = RecordSearch.run(records: records, query: RecordQuery(start: start, end: start.addingTimeInterval(2 * 86400)))
        #expect(Set(dated.map(\.id)) == [onStart.id, inside.id])
        let bounded = RecordSearch.run(records: records, query: RecordQuery(minimumAmount: 10, maximumAmount: 100))
        #expect(Set(bounded.map(\.id)) == [onStart.id, inside.id, onEnd.id])
    }

    @Test func searchCombinesWithFiltersAndSortOrdersAreDeterministic() {
        let cash = UUID()
        let matching = record(amount: 20, day: 1, account: cash, payee: "Bakery")
        let filteredOut = record(amount: 30, day: 2, account: UUID(), payee: "Bakery")
        let noText = record(amount: 40, day: 3, account: cash, payee: "Garage")
        let records = [matching, filteredOut, noText]
        let combined = RecordSearch.run(records: records, query: RecordQuery(text: "bakery", accountIDs: [cash]))
        #expect(combined.map(\.id) == [matching.id])

        func order(_ sort: RecordSortOrder) -> [UUID] {
            RecordSearch.run(records: records, query: RecordQuery(sort: sort)).map(\.id)
        }
        #expect(order(.newest) == [noText.id, filteredOut.id, matching.id])
        #expect(order(.oldest) == [matching.id, filteredOut.id, noText.id])
        #expect(order(.largest) == [noText.id, filteredOut.id, matching.id])
        #expect(order(.smallest) == [matching.id, filteredOut.id, noText.id])
        #expect(order(.relevance) == order(.newest)) // no text: relevance falls back to newest first
    }

    @Test func inactiveQueryReturnsEveryRecordAndClearingRemovesOnlyFilters() {
        let records = [record(day: 0), record(day: 1)]
        var query = RecordQuery(text: "note", kinds: [.expense], accountIDs: [UUID()], start: start,
                                minimumAmount: 1, sort: .oldest)
        #expect(query.isActive)
        #expect(query.activeFilterCount == 4)
        query.clearFilters()
        #expect(query.activeFilterCount == 0)
        #expect(query.text == "note")
        #expect(query.sort == .oldest)
        let all = RecordSearch.run(records: records, query: RecordQuery())
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.score == 0 })
        #expect(!RecordQuery().isActive)
    }

    @Test func recentSearchesKeepNewestFirstDeduplicateAndCapTheHistory() {
        var stored = ""
        for term in ["coffee", "rent", "  ", "COFFEE"] { stored = RecentSearches.adding(term, to: stored) }
        #expect(RecentSearches.list(from: stored) == ["COFFEE", "rent"])
        for index in 0..<RecentSearches.limit { stored = RecentSearches.adding("term \(index)", to: stored) }
        let history = RecentSearches.list(from: stored)
        #expect(history.count == RecentSearches.limit)
        #expect(history.first == "term \(RecentSearches.limit - 1)")
        #expect(!history.contains("COFFEE"))
        #expect(RecentSearches.adding("   ", to: stored) == stored)
    }
}
