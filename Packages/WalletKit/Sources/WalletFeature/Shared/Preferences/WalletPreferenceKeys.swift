public enum WalletPreferenceKeys {
    public static let appearance = "settings.appearance"
    static let lastUsedAccountID = "records.lastUsedAccountID"
    static let lastUsedPaymentType = "records.lastUsedPaymentType"
    static let recentSearches = "records.recentSearches"
    /// App lock settings; the passcode verifier itself lives in the keychain, never here.
    static let appLockUseBiometrics = "security.appLock.useBiometrics"
    static let appLockGracePeriod = "security.appLock.gracePeriod"
    /// First-launch setup is per-device, so this is deliberately not synced.
    static let onboardingCompleted = "onboarding.completed"
    static let homeCurrency = "currency.home"
    static let convertTotals = "currency.convertTotals"
}
