import Foundation
import Testing
import WalletData
import WalletDomain
@testable import WalletFeature

/// Rejects every write, so the account step can be tested against a storage failure.
private final class RejectingAccountRepository: AccountRepository {
    enum Failure: Error { case rejected }

    func fetchAccounts() async throws -> [Account] { [] }
    func createAccount(_ account: Account) async throws { throw Failure.rejected }
    func updateAccount(id: UUID, name: String, type: AccountType, settings: AccountSettings) async throws {
        throw Failure.rejected
    }
    func accountDeletionImpact(id: UUID) async throws -> AccountDeletionImpact { throw Failure.rejected }
    func deleteAccount(id: UUID, strategy: AccountDeletionStrategy) async throws { throw Failure.rejected }
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

@MainActor
struct OnboardingTests {
    private func makeModel() async throws -> (OnboardingViewModel, AccountsViewModel, UserDefaults) {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let accounts = AccountsViewModel(useCases: AccountUseCases(repository: repository))
        let defaults = UserDefaults(suiteName: "onboarding.tests.\(UUID().uuidString)")!
        return (OnboardingViewModel(accounts: accounts, preferences: defaults), accounts, defaults)
    }

    @Test func completionIsFalseUntilOnboardingFinishes() async throws {
        let (model, _, defaults) = try await makeModel()
        #expect(!OnboardingViewModel.hasCompleted(preferences: defaults))

        model.finish()
        #expect(OnboardingViewModel.hasCompleted(preferences: defaults))
    }

    @Test func skippingRecordsCompletionSoOnboardingDoesNotReturn() async throws {
        let (model, _, defaults) = try await makeModel()
        model.skip()
        #expect(OnboardingViewModel.hasCompleted(preferences: defaults))
    }

    @Test func theAccountStepRequiresANameAndAValidBalance() async throws {
        let (model, _, _) = try await makeModel()
        await model.advance() // welcome -> account
        #expect(model.step == .account)
        #expect(!model.canAdvance)

        model.accountName = "  "
        #expect(!model.isAccountValid)

        model.accountName = "Everyday Cash"
        // An empty balance is allowed and means zero.
        #expect(model.isAccountValid)

        model.startingBalance = "not a number"
        #expect(!model.isAccountValid)

        model.startingBalance = "125.50"
        #expect(model.isAccountValid)
    }

    @Test func advancingPastTheAccountStepCreatesTheAccount() async throws {
        let (model, accounts, _) = try await makeModel()
        await model.advance()
        model.accountName = "Everyday Cash"
        model.accountType = .checking
        model.currencyCode = "EUR"
        model.startingBalance = "125.50"

        await model.advance()

        #expect(model.step == .categories)
        #expect(model.errorMessage == nil)
        #expect(accounts.accounts.count == 1)
        let account = try #require(accounts.accounts.first)
        #expect(account.name == "Everyday Cash")
        #expect(account.type == .checking)
        #expect(account.currencyCode == "EUR")
        #expect(account.settings.currentBalance == Decimal(string: "125.50")!)
    }

    /// A rejected account must leave the user on the step with the draft intact.
    @Test func aFailedAccountSaveKeepsTheStepAndReportsTheError() async throws {
        let defaults = UserDefaults(suiteName: "onboarding.tests.\(UUID().uuidString)")!
        let accounts = AccountsViewModel(useCases: AccountUseCases(repository: RejectingAccountRepository()))
        let model = OnboardingViewModel(accounts: accounts, preferences: defaults)

        await model.advance()
        model.accountName = "Everyday Cash"
        await model.advance()

        #expect(model.step == OnboardingViewModel.Step.account)
        #expect(model.errorMessage != nil)
        #expect(model.accountName == "Everyday Cash")
        #expect(!OnboardingViewModel.hasCompleted(preferences: defaults))
    }

    @Test func theBudgetStepIsOptionalButValidatedWhenChosen() async throws {
        let (model, _, _) = try await makeModel()
        #expect(model.isBudgetValid) // off by default

        model.wantsBudget = true
        model.budgetAmount = ""
        #expect(!model.isBudgetValid)

        model.budgetAmount = "0"
        #expect(!model.isBudgetValid) // a zero limit is not a budget

        model.budgetAmount = "600"
        #expect(model.isBudgetValid)

        model.budgetName = " "
        #expect(!model.isBudgetValid)
    }

    @Test func steppingBackNeverReturnsToTheAlreadyCreatedAccount() async throws {
        let (model, _, _) = try await makeModel()
        await model.advance()
        model.accountName = "Everyday Cash"
        await model.advance()
        #expect(model.step == .categories)

        // Categories is the earliest step reachable again; the account already exists.
        #expect(!model.canGoBack)
        model.back()
        #expect(model.step == .categories)

        await model.advance()
        #expect(model.step == .budget)
        #expect(model.canGoBack)
        model.back()
        #expect(model.step == .categories)
    }

    @Test func reachingTheEndCompletesOnboarding() async throws {
        let (model, _, defaults) = try await makeModel()
        await model.advance()
        model.accountName = "Everyday Cash"
        await model.advance() // categories
        await model.advance() // budget
        await model.advance() // ready
        #expect(model.step == .ready)
        #expect(!OnboardingViewModel.hasCompleted(preferences: defaults))

        await model.advance()
        #expect(OnboardingViewModel.hasCompleted(preferences: defaults))
    }
}
