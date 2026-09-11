import SwiftUI
import WalletFeature
#if canImport(UIKit)
    import UIKit
#endif

/// The alternate icons declared in Info.plist, and how to apply them.
///
/// Alternate icons are an iOS facility; on other platforms the list is empty and the Settings
/// section for it simply does not appear.
enum WalletAppIcons {
    static var options: [WalletAppIcon] {
        #if os(iOS)
            guard UIApplication.shared.supportsAlternateIcons else { return [] }
            return [
                // The primary icon is milk with black stripes; the swatch tile draws a white
                // symbol, so it takes the icon's ink rather than its milk.
                WalletAppIcon(alternateName: nil, title: "Default", symbol: "wallet.bifold",
                              color: Color(.sRGB, red: 0.075, green: 0.075, blue: 0.086)),
                WalletAppIcon(alternateName: "AppIcon-Midnight", title: "Midnight",
                              symbol: "moon.stars", color: Color(.sRGB, red: 0.11, green: 0.13, blue: 0.21)),
                WalletAppIcon(alternateName: "AppIcon-Forest", title: "Forest",
                              symbol: "leaf", color: Color(.sRGB, red: 0.10, green: 0.36, blue: 0.24)),
                WalletAppIcon(alternateName: "AppIcon-Sunset", title: "Sunset",
                              symbol: "sun.horizon", color: Color(.sRGB, red: 0.78, green: 0.31, blue: 0.16)),
            ]
        #else
            return []
        #endif
    }

    static func current() -> String? {
        #if os(iOS)
            UIApplication.shared.alternateIconName
        #else
            nil
        #endif
    }

    static func apply(_ name: String?) async throws {
        #if os(iOS)
            guard UIApplication.shared.supportsAlternateIcons else { return }
            // Already showing it: setting the same icon again would pointlessly alert the user.
            guard UIApplication.shared.alternateIconName != name else { return }
            try await UIApplication.shared.setAlternateIconName(name)
        #endif
    }
}
