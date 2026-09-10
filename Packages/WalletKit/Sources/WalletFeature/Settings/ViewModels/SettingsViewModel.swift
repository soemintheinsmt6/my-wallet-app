import Combine
import Foundation
import WalletDomain

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public private(set) var isResetting = false
    @Published public private(set) var resetGeneration = 0
    @Published public var errorMessage: String?
    private let resetUseCase: ResetWalletUseCase
    private let preferences: UserDefaults
    /// Called after a successful reset so shared caches outside the store — the widget snapshot —
    /// can be cleared too.
    public var onReset: (() -> Void)?

    public init(resetUseCase: ResetWalletUseCase, preferences: UserDefaults = .standard) {
        self.resetUseCase = resetUseCase
        self.preferences = preferences
    }

    public func resetData() async {
        guard !isResetting else { return }
        isResetting = true
        errorMessage = nil
        defer { isResetting = false }
        do {
            try await resetUseCase.execute()
            preferences.removeObject(forKey: WalletPreferenceKeys.lastUsedAccountID)
            preferences.removeObject(forKey: WalletPreferenceKeys.lastUsedPaymentType)
            preferences.removeObject(forKey: WalletPreferenceKeys.recentSearches)
            onReset?()
            resetGeneration += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
