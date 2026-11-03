import Foundation

public enum AccountValidationError: LocalizedError {
    case emptyName
    case nameTooLong
    case invalidCurrency
    case invalidBalance
    case invalidLimits
    case accountNotFound
    case saveInProgress
    case invalidAccountNumber

    public var errorDescription: String? {
        switch self {
        case .emptyName: "Enter an account name."
        case .nameTooLong: "Use an account name with 80 characters or fewer."
        case .invalidCurrency: "Choose a valid currency."
        case .invalidBalance: "Enter valid amounts with up to 18 digits and 8 decimal places."
        case .invalidLimits: "Minimum balance must be less than maximum balance when both notifications are enabled."
        case .accountNotFound: "This account no longer exists. Close this form and refresh your accounts."
        case .saveInProgress: "Another account is being saved. Please try again."
        case .invalidAccountNumber: "Use up to 34 letters, digits, spaces or dashes for the account number."
        }
    }
}

@MainActor
public struct AccountUseCases {
    private let repository: any AccountRepository

    public init(repository: any AccountRepository) { self.repository = repository }

    public func load() async throws -> [Account] { try await repository.fetchAccounts() }

    public func create(name: String, type: AccountType, currencyCode: String = "USD", settings: AccountSettings = AccountSettings()) async throws {
        let trimmedName = try validate(name: name, settings: settings)
        let settings = try withValidatedNumber(settings, type: type)
        guard Locale.commonISOCurrencyCodes.contains(currencyCode) else { throw AccountValidationError.invalidCurrency }
        try Task.checkCancellation()
        try await repository.createAccount(Account(name: trimmedName, type: type, currencyCode: currencyCode, settings: settings))
    }

    public func update(id: UUID, name: String, type: AccountType, settings: AccountSettings) async throws {
        let trimmedName = try validate(name: name, settings: settings)
        let settings = try withValidatedNumber(settings, type: type)
        try Task.checkCancellation()
        try await repository.updateAccount(id: id, name: trimmedName, type: type, settings: settings)
    }

    /// Trims the number and checks its characters. A type without numbers, cash, drops any number,
    /// so switching an account to cash cannot leave a hidden one behind.
    private func withValidatedNumber(_ settings: AccountSettings, type: AccountType) throws -> AccountSettings {
        var settings = settings
        guard type.hasAccountNumber, let number = AccountNumber.normalized(settings.accountNumber) else {
            settings.accountNumber = nil
            return settings
        }
        guard AccountNumber.isValid(number) else { throw AccountValidationError.invalidAccountNumber }
        settings.accountNumber = number
        return settings
    }

    public func deletionImpact(id: UUID) async throws -> AccountDeletionImpact {
        try await repository.accountDeletionImpact(id: id)
    }

    public func delete(id: UUID, strategy: AccountDeletionStrategy) async throws {
        try Task.checkCancellation()
        try await repository.deleteAccount(id: id, strategy: strategy)
    }

    private func validate(name: String, settings: AccountSettings) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw AccountValidationError.emptyName }
        guard trimmedName.count <= 80 else { throw AccountValidationError.nameTooLong }
        let amounts = [settings.currentBalance, settings.minimumBalance, settings.maximumBalance]
        guard amounts.allSatisfy({ !$0.isNaN && abs($0) < Decimal(string: "1000000000000000000")! }) else {
            throw AccountValidationError.invalidBalance
        }
        for var amount in amounts {
            var rounded = Decimal()
            NSDecimalRound(&rounded, &amount, 8, .plain)
            guard amount == rounded else { throw AccountValidationError.invalidBalance }
        }
        if settings.notifyBelowMinimum && settings.notifyAboveMaximum && settings.minimumBalance >= settings.maximumBalance {
            throw AccountValidationError.invalidLimits
        }
        return trimmedName
    }

    public func changes() -> AsyncStream<Void> { repository.changes() }
}
