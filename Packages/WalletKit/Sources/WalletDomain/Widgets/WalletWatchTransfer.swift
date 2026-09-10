import Foundation

/// The payload vocabulary shared by the phone and the watch.
///
/// Both sides encode to a plain dictionary because `WCSession` only carries property-list values.
/// Keeping the encoding here means neither side can drift from the other.
public enum WalletWatchTransfer {
    public static let snapshotKey = "snapshot"
    public static let expenseKey = "expense"

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode(snapshot: WalletSnapshot) throws -> [String: Any] {
        [snapshotKey: try encoder.encode(snapshot)]
    }

    public static func decodeSnapshot(from payload: [String: Any]) -> WalletSnapshot? {
        guard let data = payload[snapshotKey] as? Data else { return nil }
        return try? decoder.decode(WalletSnapshot.self, from: data)
    }

    public static func encode(expense: WalletSnapshot.QuickExpense) throws -> [String: Any] {
        [expenseKey: try encoder.encode(expense)]
    }

    public static func decodeExpense(from payload: [String: Any]) -> WalletSnapshot.QuickExpense? {
        guard let data = payload[expenseKey] as? Data else { return nil }
        return try? decoder.decode(WalletSnapshot.QuickExpense.self, from: data)
    }
}
