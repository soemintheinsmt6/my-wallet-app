import Foundation

@MainActor
public protocol DrinkingDayRepository: AnyObject {
    func fetchDrinkingDays() async throws -> [DrinkingDay]
    /// Replaces whatever is stored for the same day.
    func saveDrinkingDay(_ day: DrinkingDay) async throws
    func deleteDrinkingDay(_ day: DayKey) async throws
    func changes() -> AsyncStream<Void>
}
