public enum WalletPreferenceKeys {
    public static let appearance = "settings.appearance"
    static let lastUsedAccountID = "records.lastUsedAccountID"
    static let lastUsedPaymentType = "records.lastUsedPaymentType"
    static let recentSearches = "records.recentSearches"
    /// App lock settings; the passcode verifier itself lives in the keychain, never here.
    static let appLockUseBiometrics = "security.appLock.useBiometrics"
    static let appLockGracePeriod = "security.appLock.gracePeriod"
}
