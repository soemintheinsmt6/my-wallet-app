import SwiftUI
import WalletDomain
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
                // The primary icon is an ink wallet on milk; the swatch tile draws a white symbol,
                // so it takes the icon's ink rather than its milk. The others take their icon's
                // background color.
                WalletAppIcon(alternateName: nil, title: "Default", symbol: WalletSymbols.wallet,
                              color: Color(.sRGB, red: 0.075, green: 0.075, blue: 0.086)),
                WalletAppIcon(alternateName: "AppIcon-Midnight", title: "Midnight",
                              symbol: "moon.stars", color: Color(.sRGB, red: 0.16, green: 0.19, blue: 0.32)),
                WalletAppIcon(alternateName: "AppIcon-Forest", title: "Forest",
                              symbol: "leaf", color: Color(.sRGB, red: 0.13, green: 0.44, blue: 0.29)),
                WalletAppIcon(alternateName: "AppIcon-Sunset", title: "Sunset",
                              symbol: "sun.horizon", color: Color(.sRGB, red: 0.87, green: 0.35, blue: 0.17)),
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
