import Foundation

/// Fixed sRGB colors shared by category UI and charts. Never derive these from nature.
///
/// Tuned as a set (2026-11-01) to sit beside the system green and red used for income and
/// expense: each hue at the most saturation sRGB allows, as light as one value can be and still
/// work in light and dark mode (OKLCH lightness 0.50–0.67, chroma >= 0.10). Each neighbor in this
/// order stays apart under deutan/protan simulation (ΔE >= 10.2) and normal vision (ΔE >= 17.5).
/// A few fall just under 3:1 against a surface (green, blue, teal and gold on white; brown on
/// black), so charts must always name each category in text, never rely on color alone; ten hues
/// cannot all stay apart in every pairing either. Transportation is brown rather than slate gray,
/// which read as gray and shared Shopping's hue. Re-validate the whole set if any value changes.
public enum CategoryColor: UInt32, CaseIterable, Sendable {
    case food = 0x05B231
    case shopping = 0x009EDB
    case housing = 0xD47A05
    case transportation = 0x964B2C
    case vehicle = 0xA834FF
    case entertainment = 0xFE2826
    case communication = 0x5555FF
    case financial = 0x09AB99
    case investments = 0xD40363
    case income = 0xB29000

    public var hex: String { String(format: "#%06X", rawValue) }
}

public extension WalletCategory {
    /// Children intentionally share the root's series color, including custom children.
    /// Uses stable IDs so names, nature, sorting and app restarts cannot change the color.
    var colorToken: CategoryColor {
        Self.color(forRootID: parentID ?? id)
    }

    private static func color(forRootID id: UUID) -> CategoryColor {
        let roots = CategorySeeds.categories.filter { $0.parentID == nil }
        let palette: [CategoryColor] = [.food, .shopping, .housing, .transportation, .vehicle,
                                        .entertainment, .communication, .financial, .investments, .income]
        if let index = roots.firstIndex(where: { $0.id == id }) { return palette[index] }
        // FNV-1a is deterministic across devices; Swift's Hasher is process-randomized.
        let hash = id.uuidString.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
