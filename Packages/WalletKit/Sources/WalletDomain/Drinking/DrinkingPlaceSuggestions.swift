import Foundation

/// Places already named on drinking days, offered while one is added so each is spelled the same
/// way every time.
///
/// Spellings that differ only in case or accents ("Blue Bar", "blue bar") are one place, offered
/// under the spelling used most often. Typed text matches the start of a place or of any word in
/// it, like payees: places the text starts come first, then the most visited, then the most
/// recent. With nothing typed, the most recently visited are offered.
public struct DrinkingPlaceSuggestions: Sendable {
    private struct Place: Sendable {
        let name: String
        let folded: String
        let count: Int
        let lastVisited: DayKey
    }

    private var places: [Place] = []

    public init() {}

    public init(days: [DrinkingDay]) {
        var groups: [String: [String: (count: Int, last: DayKey)]] = [:]
        for day in days {
            for name in DrinkingDay.normalizedPlaces(day.places) {
                let tally = groups[PayeeSuggestions.fold(name), default: [:]][name]
                groups[PayeeSuggestions.fold(name), default: [:]][name] =
                    (count: (tally?.count ?? 0) + 1, last: max(tally?.last ?? day.day, day.day))
            }
        }
        places = groups.compactMap { folded, spellings in
            guard let best = spellings.max(by: { ($0.value.count, $0.value.last) < ($1.value.count, $1.value.last) }),
                  let lastVisited = spellings.values.map(\.last).max() else { return nil }
            return Place(name: best.key, folded: folded,
                         count: spellings.values.reduce(0) { $0 + $1.count }, lastVisited: lastVisited)
        }
    }

    /// The spelling already in use for `name`, ignoring case, accents and spacing, or `name`
    /// itself, single-lined, for a new place.
    public func spelling(of name: String) -> String {
        let name = DrinkingDay.normalizedPlace(name)
        let folded = PayeeSuggestions.fold(name)
        return places.first { $0.folded == folded }?.name ?? name
    }

    /// Up to `limit` places for the text typed so far, leaving out those already added to the day
    /// and one typed in full.
    public func suggestions(for text: String, excluding added: [String] = [], limit: Int = 8) -> [String] {
        guard limit > 0 else { return [] }
        let query = PayeeSuggestions.fold(DrinkingDay.normalizedPlace(text))
        let excluded = Set(added.map { PayeeSuggestions.fold(DrinkingDay.normalizedPlace($0)) })
        let candidates = places.filter { !excluded.contains($0.folded) }
        guard !query.isEmpty else {
            return candidates
                .sorted { ($0.lastVisited, $0.count, $1.name) > ($1.lastVisited, $1.count, $0.name) }
                .prefix(limit).map(\.name)
        }
        return candidates
            .filter { $0.folded != query && PayeeSuggestions.startsWord(query, in: $0.folded) }
            .map { (place: $0, isPrefix: $0.folded.hasPrefix(query)) }
            .sorted { lhs, rhs in
                if lhs.isPrefix != rhs.isPrefix { return lhs.isPrefix }
                return (lhs.place.count, lhs.place.lastVisited, rhs.place.name)
                    > (rhs.place.count, rhs.place.lastVisited, lhs.place.name)
            }
            .prefix(limit).map(\.place.name)
    }
}
