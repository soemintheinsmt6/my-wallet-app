import SwiftUI

/// Reaches the record editor, which suggests marking a drinking day for an alcohol expense,
/// without threading the drinking model through every presenter.
private struct DrinkingDaysViewModelKey: EnvironmentKey {
    static let defaultValue: DrinkingDaysViewModel? = nil
}

public extension EnvironmentValues {
    var drinkingDaysViewModel: DrinkingDaysViewModel? {
        get { self[DrinkingDaysViewModelKey.self] }
        set { self[DrinkingDaysViewModelKey.self] = newValue }
    }
}
