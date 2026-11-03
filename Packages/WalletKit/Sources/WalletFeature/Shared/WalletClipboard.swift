import Foundation
#if canImport(UIKit)
    import UIKit
    import UniformTypeIdentifiers
#elseif canImport(AppKit)
    import AppKit
#endif

/// Copies text that should not linger, such as an account number.
enum WalletClipboard {
    /// How long a sensitive copy stays on the clipboard on iOS.
    static let sensitiveLifetime: TimeInterval = 60

    /// On iOS the copy stays on this device, so Universal Clipboard does not send it to others, and
    /// expires after `sensitiveLifetime`. macOS has neither option, so it is an ordinary copy there.
    @MainActor
    static func copySensitive(_ text: String) {
        #if canImport(UIKit)
            UIPasteboard.general.setItems(
                [[UTType.plainText.identifier: text]],
                options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(sensitiveLifetime)])
        #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
