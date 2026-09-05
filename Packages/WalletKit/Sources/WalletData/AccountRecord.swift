import Foundation
import SwiftData
import WalletDomain

@Model
final class AccountRecord {
    var id: UUID = UUID()
    var name: String = ""
    var typeRawValue: String = "other"
    var createdAt: Date = Date()
    var currencyCode: String = "USD"
    // Canonical decimal strings avoid binary floating-point loss and sync as CloudKit strings.
    var balanceValue: String = "0"
    var colorValue: String = "blue"
    var notifyBelowMinimum: Bool = false
    var minimumBalanceValue: String = "0"
    var notifyAboveMaximum: Bool = false
    var maximumBalanceValue: String = "0"
    var excludeFromStats: Bool = false

    init(account: Account) {
        id = account.id
        name = account.name
        typeRawValue = account.type.rawValue
        createdAt = account.createdAt
        currencyCode = account.currencyCode
        apply(name: account.name, type: account.type, settings: account.settings)
    }

    func apply(name: String, type: AccountType, settings: AccountSettings) {
        self.name = name
        typeRawValue = type.rawValue
        balanceValue = NSDecimalNumber(decimal: settings.currentBalance).stringValue
        colorValue = settings.color.rawValue
        notifyBelowMinimum = settings.notifyBelowMinimum
        minimumBalanceValue = NSDecimalNumber(decimal: settings.minimumBalance).stringValue
        notifyAboveMaximum = settings.notifyAboveMaximum
        maximumBalanceValue = NSDecimalNumber(decimal: settings.maximumBalance).stringValue
        excludeFromStats = settings.excludeFromStats
    }

    var account: Account {
        Account(id: id, name: name, type: AccountType(rawValue: typeRawValue) ?? .other, createdAt: createdAt, currencyCode: currencyCode, settings: AccountSettings(
            currentBalance: Decimal(string: balanceValue, locale: Locale(identifier: "en_US_POSIX")) ?? 0,
            color: AccountColor(rawValue: colorValue) ?? .blue,
            notifyBelowMinimum: notifyBelowMinimum,
            minimumBalance: Decimal(string: minimumBalanceValue, locale: Locale(identifier: "en_US_POSIX")) ?? 0,
            notifyAboveMaximum: notifyAboveMaximum,
            maximumBalance: Decimal(string: maximumBalanceValue, locale: Locale(identifier: "en_US_POSIX")) ?? 0,
            excludeFromStats: excludeFromStats
        ))
    }
}
