public enum WalletPreferenceKeys {
    public static let appearance = "settings.appearance"
    static let lastUsedAccountID = "records.lastUsedAccountID"
    static let lastUsedPaymentType = "records.lastUsedPaymentType"
    static let recentSearches = "records.recentSearches"
    /// App lock settings; the passcode verifier itself lives in the keychain, never here.
    static let appLockUseBiometrics = "security.appLock.useBiometrics"
    /// Set when the lock is held by biometrics alone, with no wallet passcode behind it.
    static let appLockBiometricsOnly = "security.appLock.biometricsOnly"
    static let appLockGracePeriod = "security.appLock.gracePeriod"
    /// First-launch setup is per-device, so this is deliberately not synced.
    static let onboardingCompleted = "onboarding.completed"
    static let homeCurrency = "currency.home"
    /// Prefills the currency of new accounts, bills, budgets, debts and goals.
    static let defaultCurrency = "currency.default"
    static let convertTotals = "currency.convertTotals"
    /// How short totals count large amounts: a `NumberScale` raw value.
    static let numberScale = "currency.numberScale"
    /// Proactive insight notices; all default to off.
    static let insightWeekly = "insights.weeklySummary"
    static let insightUnusual = "insights.unusualSpending"
    static let insightMonthly = "insights.monthlyComparison"
    static let insightWeekday = "insights.weekday"
    static let insightHour = "insights.hour"
    /// The dashboard arrangement, stored as encoded JSON.
    static let dashboard = "dashboard.configuration"
    /// Visual personalization; cosmetic and local, so deliberately not synced.
    static let accent = "theme.accent"
    static let density = "theme.density"
    static let textSize = "theme.textSize"
    static let categorySymbols = "theme.categorySymbols"}
