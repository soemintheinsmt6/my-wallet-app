import SwiftUI

/// Makes the app-wide currency model reachable from deep views — the record editor and detail —
/// without threading it through every call site that presents them.
///
/// Optional so previews and any screen constructed without it simply show no converted figures.
private struct CurrencyViewModelKey: EnvironmentKey {
    static let defaultValue: CurrencyViewModel? = nil
}

public extension EnvironmentValues {
    var currencyViewModel: CurrencyViewModel? {
        get { self[CurrencyViewModelKey.self] }
        set { self[CurrencyViewModelKey.self] = newValue }
    }

    /// The currency a newly created item starts in.
    @MainActor var defaultCurrency: String {
        currencyViewModel?.defaultCurrency ?? CurrencyViewModel.fallbackDefaultCurrency
    }
}
