import Foundation

/// The URL contract between the widget extension and the app.
///
/// Kept in the domain, and Foundation-only, so the widget can link `WalletDomain` alone instead of
/// pulling the whole SwiftUI feature module into the extension process.
public enum WalletDeepLink: Equatable, Sendable {
    case home
    case records
    case statistics
    case planning
    /// Opens the record editor with the kind preselected. Adding a record needs an amount, so the
    /// widget hands off to the app rather than writing anything itself.
    case addRecord(RecordKind)

    public static let scheme = "mywallet"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .home: components.host = "home"
        case .records: components.host = "records"
        case .statistics: components.host = "statistics"
        case .planning: components.host = "planning"
        case .addRecord(let kind):
            components.host = "add"
            components.queryItems = [URLQueryItem(name: "kind", value: kind.rawValue)]
        }
        // Every case above sets a host, so this is total.
        return components.url ?? URL(string: "\(Self.scheme)://home")!
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        switch url.host()?.lowercased() {
        case "home": self = .home
        case "records": self = .records
        case "statistics": self = .statistics
        case "planning": self = .planning
        case "add":
            let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "kind" }?.value
            self = .addRecord(raw.flatMap(RecordKind.init(rawValue:)) ?? .expense)
        default: return nil
        }
    }
}
