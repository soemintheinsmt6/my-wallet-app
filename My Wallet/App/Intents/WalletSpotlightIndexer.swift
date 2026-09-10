import CoreSpotlight
import Foundation
import WalletDomain
import WalletFeature

/// Publishes accounts and categories to Spotlight so they are findable from the home screen.
///
/// Only names and types are indexed — never balances or record details — because Spotlight results
/// are visible on a locked device and the app deliberately hides figures behind its own lock.
@MainActor
final class WalletSpotlightIndexer {
    static let domain = "com.app.My-Wallet.spotlight"

    private var lastIndexedSignature: String?

    func index(accounts: [Account], categories: [WalletCategory]) {
        // Skip identical work; this runs on every data change.
        let signature = accounts.map { "\($0.id)\($0.name)" }.joined()
            + categories.map { "\($0.id)\($0.name)" }.joined()
        guard signature != lastIndexedSignature else { return }
        lastIndexedSignature = signature

        var items: [CSSearchableItem] = accounts.map { account in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = account.name
            attributes.contentDescription = "\(account.type.spotlightTitle) account · \(account.currencyCode)"
            attributes.keywords = [account.name, account.currencyCode, "account", "wallet"]
            return CSSearchableItem(uniqueIdentifier: "account.\(account.id.uuidString)",
                                    domainIdentifier: Self.domain, attributeSet: attributes)
        }

        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        items += categories.map { category in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = category.name
            let parent = category.parentID.flatMap { byID[$0] }
            attributes.contentDescription = parent.map { "Subcategory of \($0.name)" } ?? "Category"
            attributes.keywords = [category.name, "category", "wallet"]
            return CSSearchableItem(uniqueIdentifier: "category.\(category.id.uuidString)",
                                    domainIdentifier: Self.domain, attributeSet: attributes)
        }

        let index = CSSearchableIndex.default()
        // Replacing the whole domain also removes anything the user deleted since the last pass.
        index.deleteSearchableItems(withDomainIdentifiers: [Self.domain]) { _ in
            index.indexSearchableItems(items) { _ in }
        }
    }

    /// Removes everything, for a wallet reset.
    func clear() {
        lastIndexedSignature = nil
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domain]) { _ in }
    }

    /// Maps a Spotlight result back to the tab that owns it.
    static func destination(for identifier: String) -> WalletTab? {
        identifier.hasPrefix("account.") || identifier.hasPrefix("category.") ? .more : nil
    }
}

private extension AccountType {
    /// A plain noun for the Spotlight subtitle; the in-app title is presentation and lives in the
    /// feature module.
    var spotlightTitle: String {
        switch self {
        case .cash: "Cash"
        case .checking: "Checking"
        case .creditCard: "Credit card"
        case .savings: "Savings"
        case .investments: "Investments"
        case .loansAndMortgage: "Loan"
        case .other: "Other"
        }
    }
}
