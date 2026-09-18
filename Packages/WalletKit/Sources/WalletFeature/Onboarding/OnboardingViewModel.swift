import Combine
import Foundation
import WalletDomain

/// Drives first-launch setup: welcome, first account, a look at the starter categories and an
/// optional first budget.
///
/// Completion is a local preference, not synced: onboarding is about getting this device usable,
/// and a wallet restored from iCloud still needs an account chosen here if it has none.
@MainActor
public final class OnboardingViewModel: ObservableObject {
    public enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case account
        case categories
        case budget
        case ready

        public var id: Int { rawValue }
    }

    @Published public private(set) var step = Step.welcome
    @Published public private(set) var isSaving = false
    @Published public var errorMessage: String?

    // First account draft.
    @Published public var accountName = ""
    @Published public var accountType = AccountType.cash
    @Published public var currencyCode = Locale.current.currency?.identifier ?? "USD"
    @Published public var startingBalance = ""

    // Optional first budget.
    @Published public var wantsBudget = false
    @Published public var budgetName = "Monthly Spending"
    @Published public var budgetAmount = ""

    private let accounts: AccountsViewModel
    private let planning: PlanningViewModel?
    private let preferences: UserDefaults

    public init(accounts: AccountsViewModel, planning: PlanningViewModel? = nil,
                preferences: UserDefaults = .standard) {
        self.accounts = accounts
        self.planning = planning
        self.preferences = preferences
    }

    public static func hasCompleted(preferences: UserDefaults = .standard) -> Bool {
        preferences.bool(forKey: WalletPreferenceKeys.onboardingCompleted)
    }

    public var isAccountValid: Bool {
        !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (try? AccountAmountInput.parseAllowingEmpty(startingBalance)) != nil
    }

    public var isBudgetValid: Bool {
        guard wantsBudget else { return true }
        guard !budgetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let amount = try? AccountAmountInput.parse(budgetAmount) else { return false }
        return amount > 0
    }

    public var canAdvance: Bool {
        switch step {
        case .account: isAccountValid && !isSaving
        case .budget: isBudgetValid && !isSaving
        default: !isSaving
        }
    }

    public var isLastStep: Bool { step == .ready }

    /// Moves to the next step, performing that step's work first.
    public func advance() async {
        errorMessage = nil
        switch step {
        case .account:
            guard await createAccount() else { return }
        case .budget:
            guard await createBudgetIfWanted() else { return }
        case .ready:
            finish()
            return
        default:
            break
        }
        guard let next = Step(rawValue: step.rawValue + 1) else { finish(); return }
        step = next
    }

    public func back() {
        // The account is already created by the time later steps are shown, so stepping back
        // stops at the categories overview rather than offering to create it again.
        guard let previous = Step(rawValue: step.rawValue - 1), previous != .account else { return }
        errorMessage = nil
        step = previous
    }

    public var canGoBack: Bool {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return false }
        return previous != .account && step != .welcome
    }

    /// Skips the rest of setup. Any account already created is kept.
    public func skip() {
        finish()
    }

    public func finish() {
        preferences.set(true, forKey: WalletPreferenceKeys.onboardingCompleted)
        NotificationCenter.default.post(name: .walletOnboardingFinished, object: nil)
    }

    private func createAccount() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            let balance = try AccountAmountInput.parseAllowingEmpty(startingBalance)
            try await accounts.create(name: accountName.trimmingCharacters(in: .whitespacesAndNewlines),
                                      type: accountType, currencyCode: currencyCode,
                                      settings: AccountSettings(currentBalance: balance))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func createBudgetIfWanted() async -> Bool {
        guard wantsBudget, let planning else { return true }
        isSaving = true
        defer { isSaving = false }
        do {
            var budget = Budget(name: budgetName.trimmingCharacters(in: .whitespacesAndNewlines),
                                amount: try AccountAmountInput.parse(budgetAmount),
                                currencyCode: currencyCode)
            budget.startDate = Calendar.current.startOfDay(for: Date())
            try await planning.save(budget)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

public extension Notification.Name {
    /// Posted when onboarding completes so the root view can swap in the tabs.
    static let walletOnboardingFinished = Notification.Name("wallet.onboarding.finished")
}
