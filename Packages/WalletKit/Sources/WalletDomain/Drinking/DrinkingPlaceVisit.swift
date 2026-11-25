import Foundation

/// How often one place appears on drinking days. Spellings that differ only in case or accents
/// ("Blue Bar", "blue bar") are one place, named by the spelling used most often.
///
/// Visits count days, not drinks: a day can name several places but records one drink count, so
/// its drinks cannot be shared out between them. A night at two places counts for both.
public struct DrinkingPlaceVisit: Equatable, Sendable {
    public let name: String
    public let visits: Int
    public let lastVisited: DayKey

    public init(name: String, visits: Int, lastVisited: DayKey) {
        self.name = name
        self.visits = visits
        self.lastVisited = lastVisited
    }

    /// The most visited places across `days`, most visits first, then the most recently visited,
    /// then by name, so equal places keep a steady order.
    public static func mostVisited(in days: [DrinkingDay], limit: Int = 5) -> [DrinkingPlaceVisit] {
        guard limit > 0 else { return [] }
        return tally(days).map(\.visit)
            .sorted { ($0.visits, $0.lastVisited, $1.name) > ($1.visits, $1.lastVisited, $0.name) }
            .prefix(limit).map { $0 }
    }

    /// Every place across `days`, each once with its folded name for matching.
    static func tally(_ days: [DrinkingDay]) -> [(folded: String, visit: DrinkingPlaceVisit)] {
        var groups: [String: [String: (count: Int, last: DayKey)]] = [:]
        for day in days {
            for name in DrinkingDay.normalizedPlaces(day.places) {
                let folded = PayeeSuggestions.fold(name)
                let tally = groups[folded, default: [:]][name]
                groups[folded, default: [:]][name] =
                    (count: (tally?.count ?? 0) + 1, last: max(tally?.last ?? day.day, day.day))
            }
        }
        return groups.compactMap { folded, spellings in
            guard let best = spellings.max(by: { ($0.value.count, $0.value.last) < ($1.value.count, $1.value.last) }),
                  let lastVisited = spellings.values.map(\.last).max() else { return nil }
            let visits = spellings.values.reduce(0) { $0 + $1.count }
            return (folded, DrinkingPlaceVisit(name: best.key, visits: visits, lastVisited: lastVisited))
        }
    }
}
