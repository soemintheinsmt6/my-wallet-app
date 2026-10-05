import Foundation

@MainActor
public struct DrinkingDayUseCases {
    private let repository: any DrinkingDayRepository

    public init(repository: any DrinkingDayRepository) { self.repository = repository }

    public func load() async throws -> [DrinkingDay] { try await repository.fetchDrinkingDays() }

    public func mark(_ day: DayKey, drinks: Int?, note: String,
                     today: DayKey = DayKey(Date())) async throws {
        guard day <= today else { throw DrinkingDayError.futureDay }
        if let drinks {
            guard (1...DrinkingDay.maximumDrinks).contains(drinks) else { throw DrinkingDayError.invalidDrinks }
        }
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count <= DrinkingDay.maximumNoteLength else { throw DrinkingDayError.noteTooLong }
        try Task.checkCancellation()
        try await repository.saveDrinkingDay(DrinkingDay(day: day, drinks: drinks, note: note))
    }

    public func unmark(_ day: DayKey) async throws {
        try Task.checkCancellation()
        try await repository.deleteDrinkingDay(day)
    }

    public func changes() -> AsyncStream<Void> { repository.changes() }
}
