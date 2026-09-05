@MainActor
public protocol WalletResetRepository: AnyObject {
    func resetWalletData() async throws
}
