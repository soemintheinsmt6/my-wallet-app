import Foundation
import SwiftData
import WalletDomain

/// One marked day. CloudKit cannot enforce uniqueness, so two devices marking the same day offline
/// can both upload a row; reads keep the newest per `dayValue` and saves fold the extras away.
/// Every property is defaulted, keeping this an additive, CloudKit-compatible model.
@Model
final class DrinkingDayRecord {
    var dayValue: String = ""
    var drinks: Int?
    var note: String = ""
    var updatedAt: Date = Date()

    init(day: DrinkingDay) {
        dayValue = day.day.rawValue
        apply(day)
    }

    func apply(_ day: DrinkingDay) {
        drinks = day.drinks
        note = day.note
        updatedAt = day.updatedAt
    }

    var drinkingDay: DrinkingDay? {
        guard let key = DayKey(rawValue: dayValue) else { return nil }
        return DrinkingDay(day: key, drinks: drinks, note: note, updatedAt: updatedAt)
    }
}
