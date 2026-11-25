import Foundation

@MainActor
public struct DrinkingDayUseCases {
    private let repository: any DrinkingDayRepository

    public init(repository: any DrinkingDayRepository) { self.repository = repository }

    public func load() async throws -> [DrinkingDay] { try await repository.fetchDrinkingDays() }

    /// Saves the day as it will be stored and returns it: the note trimmed, and each place on one
    /// line and listed once.
    @discardableResult
    public func mark(_ day: DayKey, drinks: Int?, places: [String] = [], note: String,
                     today: DayKey = DayKey(Date())) async throws -> DrinkingDay {
        guard day <= today else { throw DrinkingDayError.futureDay }
        if let drinks {
            guard (1...DrinkingDay.maximumDrinks).contains(drinks) else { throw DrinkingDayError.invalidDrinks }
        }
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count <= DrinkingDay.maximumNoteLength else { throw DrinkingDayError.noteTooLong }
        let places = DrinkingDay.normalizedPlaces(places)
        guard places.count <= DrinkingDay.maximumPlaces else { throw DrinkingDayError.tooManyPlaces }
        guard places.allSatisfy({ $0.count <= DrinkingDay.maximumPlaceNameLength }) else {
            throw DrinkingDayError.placeNameTooLong
        }
        try Task.checkCancellation()
        let saved = DrinkingDay(day: day, drinks: drinks, places: places, note: note)
        try await repository.saveDrinkingDay(saved)
        return saved
    }

    public func unmark(_ day: DayKey) async throws {
        try Task.checkCancellation()
        try await repository.deleteDrinkingDay(day)
    }

    public func changes() -> AsyncStream<Void> { repository.changes() }
}
