import Foundation
import SwiftData
import WalletDomain

extension WalletStore {
    func fetchDrinkingDays() throws -> [DrinkingDay] {
        let context = ModelContext(modelContainer)
        var newest: [DayKey: DrinkingDay] = [:]
        for day in try context.fetch(FetchDescriptor<DrinkingDayRecord>()).compactMap(\.drinkingDay) {
            if let kept = newest[day.day], kept.updatedAt >= day.updatedAt { continue }
            newest[day.day] = day
        }
        return newest.values.sorted { $0.day > $1.day }
    }

    func saveDrinkingDay(_ day: DrinkingDay) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let value = day.day.rawValue
        let records = try context.fetch(FetchDescriptor<DrinkingDayRecord>(predicate: #Predicate { $0.dayValue == value }))
        if let first = records.first {
            first.apply(day)
            // Fold away copies another device uploaded for the same day.
            for extra in records.dropFirst() { context.delete(extra) }
        } else {
            context.insert(DrinkingDayRecord(day: day))
        }
        try context.save()
    }

    func deleteDrinkingDay(_ day: DayKey) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let value = day.rawValue
        // Removing an unmarked day is a no-op, so a repeat from another window is safe.
        for record in try context.fetch(FetchDescriptor<DrinkingDayRecord>(predicate: #Predicate { $0.dayValue == value })) {
            context.delete(record)
        }
        if context.hasChanges { try context.save() }
    }
}
