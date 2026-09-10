import Foundation

/// Newest-first search history kept in a single newline-separated preference string.
///
/// Terms are trimmed, compared case- and diacritic-insensitively for de-duplication and
/// capped at `limit`. The history is a local device convenience and is not synchronized.
enum RecentSearches {
    static let limit = 8
    private static let maximumTermLength = 120

    static func list(from stored: String) -> [String] {
        stored.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func adding(_ term: String, to stored: String) -> String {
        let trimmed = String(term.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumTermLength))
        guard !trimmed.isEmpty else { return stored }
        let remaining = list(from: stored).filter { $0.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame }
        return ([trimmed] + remaining).prefix(limit).joined(separator: "\n")
    }
}
