import Combine
import SwiftUI

/// Accent colors the user can choose. Fixed sRGB values, so a theme looks the same on every device.
/// There is no blue: Default is the system blue on iOS, so a fixed blue would repeat it. A stored
/// "blue" from before it was removed no longer matches a case and loads as Default.
public enum WalletAccent: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case indigo
    case purple
    case pink
    case red
    case orange
    case green
    case teal

    public var id: String { rawValue }

    public var title: String { rawValue == "system" ? "Default" : rawValue.capitalized }

    /// `nil` keeps the asset catalog's accent color, so "Default" really is the system default.
    public var color: Color? {
        switch self {
        case .system: nil
        case .indigo: Color(.sRGB, red: 0.35, green: 0.34, blue: 0.84)
        case .purple: Color(.sRGB, red: 0.69, green: 0.32, blue: 0.87)
        case .pink: Color(.sRGB, red: 1.00, green: 0.18, blue: 0.33)
        case .red: Color(.sRGB, red: 0.88, green: 0.19, blue: 0.16)
        case .orange: Color(.sRGB, red: 1.00, green: 0.58, blue: 0.00)
        case .green: Color(.sRGB, red: 0.20, green: 0.72, blue: 0.29)
        case .teal: Color(.sRGB, red: 0.19, green: 0.69, blue: 0.78)
        }
    }

    /// Always shows something, so the picker has a swatch for Default too. Default draws the
    /// system's own accent as a concrete color, never `.accentColor`: the app tints everything
    /// with the chosen accent, so `.accentColor` would turn Default's swatch into the selection.
    public var swatch: Color { color ?? Self.systemAccent }

    private static var systemAccent: Color {
        #if os(macOS)
        Color(nsColor: .controlAccentColor)
        #else
        Color(uiColor: .systemBlue)
        #endif
    }
}

/// How much breathing room list rows get.
public enum WalletDensity: String, CaseIterable, Codable, Sendable, Identifiable {
    case compact
    case comfortable

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }

    /// Extra vertical padding added to rows beyond the built-in minimum.
    public var extraRowPadding: CGFloat {
        switch self {
        case .compact: 0
        case .comfortable: 6
        }
    }
}

/// A text-size nudge applied on top of the system's Dynamic Type setting.
///
/// Deliberately a relative adjustment rather than a replacement: overriding Dynamic Type outright
/// would ignore an accessibility setting the user already made at the system level.
public enum WalletTextSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case small
    case standard
    case large
    case larger

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .small: "Small"
        case .standard: "Standard"
        case .large: "Large"
        case .larger: "Larger"
        }
    }

    /// `nil` leaves the system size untouched.
    public var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .small: .small
        case .standard: nil
        case .large: .large
        case .larger: .xxLarge
        }
    }
}

/// The user's visual preferences.
@MainActor
public final class ThemeViewModel: ObservableObject {
    @Published public var accent: WalletAccent {
        didSet { store(accent.rawValue, WalletPreferenceKeys.accent, oldValue.rawValue) }
    }
    @Published public var density: WalletDensity {
        didSet { store(density.rawValue, WalletPreferenceKeys.density, oldValue.rawValue) }
    }
    @Published public var textSize: WalletTextSize {
        didSet { store(textSize.rawValue, WalletPreferenceKeys.textSize, oldValue.rawValue) }
    }
    /// The alternate app icon in use, or `nil` for the default.
    @Published public private(set) var iconName: String?
    @Published public var errorMessage: String?

    private let defaults: UserDefaults
    private let iconSetter: (String?) async throws -> Void
    private let iconReader: () -> String?

    public init(defaults: UserDefaults = .standard,
                iconReader: @escaping () -> String? = { nil },
                iconSetter: @escaping (String?) async throws -> Void = { _ in }) {
        self.defaults = defaults
        self.iconReader = iconReader
        self.iconSetter = iconSetter
        accent = WalletAccent(rawValue: defaults.string(forKey: WalletPreferenceKeys.accent) ?? "") ?? .system
        density = WalletDensity(rawValue: defaults.string(forKey: WalletPreferenceKeys.density) ?? "") ?? .compact
        textSize = WalletTextSize(rawValue: defaults.string(forKey: WalletPreferenceKeys.textSize) ?? "") ?? .standard
        iconName = iconReader()
    }

    public func setIcon(_ name: String?) async {
        do {
            try await iconSetter(name)
            iconName = iconReader()
            errorMessage = nil
        } catch {
            errorMessage = "That app icon could not be applied."
        }
    }

    private func store(_ value: String, _ key: String, _ previous: String) {
        guard value != previous else { return }
        defaults.set(value, forKey: key)
    }
}

/// Applies the chosen theme to a view tree.
public struct WalletThemeModifier: ViewModifier {
    @ObservedObject var theme: ThemeViewModel

    public init(theme: ThemeViewModel) { self.theme = theme }

    public func body(content: Content) -> some View {
        content
            .tint(theme.accent.color)
            .environment(\.walletDensity, theme.density)
            // Only applied when the user asked for a nudge, so the system setting otherwise wins.
            .modifier(TextSizeModifier(size: theme.textSize.dynamicTypeSize))
    }
}

private struct TextSizeModifier: ViewModifier {
    let size: DynamicTypeSize?

    func body(content: Content) -> some View {
        if let size {
            content.dynamicTypeSize(size)
        } else {
            content
        }
    }
}

private struct WalletDensityKey: EnvironmentKey {
    static let defaultValue = WalletDensity.compact
}

public extension EnvironmentValues {
    var walletDensity: WalletDensity {
        get { self[WalletDensityKey.self] }
        set { self[WalletDensityKey.self] = newValue }
    }
}

public extension View {
    /// A list row's vertical padding: the row's own `base`, plus whatever the List Density setting
    /// adds, read from the environment so every list follows the setting without passing it down.
    func walletListRowPadding(_ base: CGFloat) -> some View {
        modifier(WalletListRowPadding(base: base))
    }
}

private struct WalletListRowPadding: ViewModifier {
    let base: CGFloat
    @Environment(\.walletDensity) private var density

    func body(content: Content) -> some View {
        content.padding(.vertical, base + density.extraRowPadding)
    }
}
