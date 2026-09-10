import Foundation

public enum WalletSnapshotError: LocalizedError, Equatable {
    case containerUnavailable

    public var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            "The shared App Group container is unavailable. Widgets will keep their last summary."
        }
    }
}

/// Reads and writes the widget snapshot in the App Group container shared by the app and the
/// widget extension.
///
/// Writes go through a temporary file and an atomic replace so a widget reload that lands
/// mid-write never sees a truncated file. A failure here is never fatal: the app keeps working and
/// widgets keep showing their previous summary.
public enum WalletSnapshotStore {
    /// Must match the App Group entitlement on both the app and the widget extension.
    public static let appGroupID = "group.com.app.My-Wallet"

    public static let fileName = "wallet-snapshot.json"

    public static func containerURL(groupID: String = appGroupID) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    public static func fileURL(groupID: String = appGroupID) -> URL? {
        containerURL(groupID: groupID)?.appendingPathComponent(fileName, isDirectory: false)
    }

    public static func write(_ snapshot: WalletSnapshot, groupID: String = appGroupID) throws {
        guard let url = fileURL(groupID: groupID) else { throw WalletSnapshotError.containerUnavailable }
        try write(snapshot, to: url)
    }

    /// Directly addressable so tests can exercise the encode/replace path without an App Group.
    public static func write(_ snapshot: WalletSnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)", isDirectory: false)
        try data.write(to: temporary, options: .atomic)
        // `replaceItemAt` removes the temporary file whether or not a previous snapshot existed.
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }

    /// Returns `nil` rather than throwing: a missing or unreadable snapshot is a normal state
    /// before the app has run, and the widget renders its empty case for it.
    public static func read(groupID: String = appGroupID) -> WalletSnapshot? {
        guard let url = fileURL(groupID: groupID) else { return nil }
        return read(from: url)
    }

    public static func read(from url: URL) -> WalletSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WalletSnapshot.self, from: data)
    }

    public static func clear(groupID: String = appGroupID) {
        guard let url = fileURL(groupID: groupID) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
