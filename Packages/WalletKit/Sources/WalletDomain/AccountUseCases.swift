import Foundation

public enum AccountValidationError: LocalizedError {
    case emptyName
    case nameTooLong
    case invalidCurrency
    case invalidBalance
    case invalidLimits
    case accountNotFound
    case saveInProgress

    public var errorDescription: String? {
        switch self {
        case .emptyName: "Enter an account name."
        case .nameTooLong: "Use an account name with 80 characters or fewer."
        case .invalidCurrency: "Choose a valid currency."
        case .invalidBalance: "Enter valid amounts with up to 18 digits and 8 decimal places."
        case .invalidLimits: "Minimum balance must be less than maximum balance when both notifications are enabled."
        case .accountNotFound: "This account no longer exists. Close this form and refresh your accounts."
        case .saveInProgress: "Another account is being saved. Please try again."
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
        guard Locale.commonISOCurrencyCodes.contains(currencyCode) else { throw AccountValidationError.invalidCurrency }
        try Task.checkCancellation()
        try await repository.createAccount(Account(name: trimmedName, type: type, currencyCode: currencyCode, settings: settings))
    }

    public func update(id: UUID, name: String, type: AccountType, settings: AccountSettings) async throws {
        let trimmedName = try validate(name: name, settings: settings)
        try Task.checkCancellation()
        try await repository.updateAccount(id: id, name: trimmedName, type: type, settings: settings)
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
