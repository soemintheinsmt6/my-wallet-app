import Foundation

/// Fixed sRGB colors shared by category UI and future charts. Never derive these from nature.
public enum CategoryColor: UInt32, CaseIterable, Sendable {
    case food = 0x55D80B
    case shopping = 0x4AC3F2
    case housing = 0xFFA51F
    case transportation = 0x78909C
    case vehicle = 0xAA00FF
    case entertainment = 0xFF4136
    case communication = 0x536DFE
    case financial = 0x00BFA5
    case investments = 0xFF4081
    case income = 0xFFC329

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
