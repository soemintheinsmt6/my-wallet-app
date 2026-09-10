import SwiftUI

/// Reaches the record editor without threading the splits model through every presenter, as the
/// currency model and receipt storage already do.
private struct SplitsViewModelKey: EnvironmentKey {
    static let defaultValue: SplitsViewModel? = nil
}

public extension EnvironmentValues {
    var splitsViewModel: SplitsViewModel? {
        get { self[SplitsViewModelKey.self] }
        set { self[SplitsViewModelKey.self] = newValue }
    }
}
