import SwiftUI
import WalletDomain

/// Reaches the record editor and detail without threading receipt storage through every screen
/// that presents them, matching how the currency model is provided.
private struct ReceiptUseCasesKey: EnvironmentKey {
    static let defaultValue: ReceiptUseCases? = nil
}

public extension EnvironmentValues {
    var receiptUseCases: ReceiptUseCases? {
        get { self[ReceiptUseCasesKey.self] }
        set { self[ReceiptUseCasesKey.self] = newValue }
    }
}
