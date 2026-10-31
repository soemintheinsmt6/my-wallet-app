import SwiftUI
import WalletDomain

/// Per-account icon choices.
///
/// Stored locally, as category icons are: an icon is a purely cosmetic preference, and a synced
/// field would mean a schema change for it. Without a choice, an account shows its type's icon, so
/// changing the type still changes the icon until one is picked.
@MainActor
public final class AccountSymbolStore: ObservableObject {
    @Published private var overrides: [String: String]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        overrides = defaults.dictionary(forKey: WalletPreferenceKeys.accountSymbols) as? [String: String] ?? [:]
    }

    public func symbol(for account: Account) -> String {
        overrides[account.id.uuidString] ?? account.type.symbol
    }

    public func hasOverride(_ account: Account) -> Bool {
        overrides[account.id.uuidString] != nil
    }

    public func set(_ symbol: String, for account: Account) {
        overrides[account.id.uuidString] = symbol
        save()
    }

    public func clear(_ account: Account) {
        overrides.removeValue(forKey: account.id.uuidString)
        save()
    }

    private func save() {
        defaults.set(overrides, forKey: WalletPreferenceKeys.accountSymbols)
    }
}

/// Reaches every account icon so a custom choice applies everywhere at once.
private struct AccountSymbolStoreKey: EnvironmentKey {
    static let defaultValue: AccountSymbolStore? = nil
}

public extension EnvironmentValues {
    var accountSymbolStore: AccountSymbolStore? {
        get { self[AccountSymbolStoreKey.self] }
        set { self[AccountSymbolStoreKey.self] = newValue }
    }
}

/// Hands its content the account's current icon, redrawing when the choice changes.
struct AccountSymbolReader<Content: View>: View {
    let account: Account
    @ViewBuilder let content: (String) -> Content
    @Environment(\.accountSymbolStore) private var symbols

    var body: some View {
        // An environment object is only read, not observed, so the observing view is what redraws
        // icons already on screen after a new choice.
        if let symbols {
            ObservingAccountSymbol(account: account, symbols: symbols, content: content)
        } else {
            content(account.type.symbol)
        }
    }
}

private struct ObservingAccountSymbol<Content: View>: View {
    let account: Account
    @ObservedObject var symbols: AccountSymbolStore
    let content: (String) -> Content

    var body: some View { content(symbols.symbol(for: account)) }
}
