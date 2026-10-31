import SwiftUI

extension Color {
    /// A deep blood red for expense amounts being entered.
    ///
    /// Deeper than system red on light backgrounds (about 6:1 against white). On dark backgrounds
    /// a deep red would sink into the black, so it lifts to a brighter crimson (about 4.3:1
    /// against black) that still reads as blood red rather than as an alert.
    static let walletExpense = adaptive(light: (0.75, 0.08, 0.12), dark: (0.84, 0.15, 0.24))

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
        #elseif os(watchOS)
        // The watch is always dark.
        Color(.sRGB, red: dark.0, green: dark.1, blue: dark.2)
        #else
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
        #endif
    }
}
