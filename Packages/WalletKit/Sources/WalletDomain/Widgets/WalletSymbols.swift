/// SF Symbol names for the app's wallet icon, shared by the app, its widgets and the watch.
///
/// `wallet.bifold` arrived in iOS 18, macOS 15, watchOS 11 and visionOS 2. On older systems an
/// unknown symbol name draws nothing, so those get `wallet.pass` instead, which every supported
/// system has.
public enum WalletSymbols {
    public static var wallet: String {
        if #available(iOS 18, macOS 15, watchOS 11, visionOS 2, *) { "wallet.bifold" } else { "wallet.pass" }
    }

    public static var walletFill: String {
        if #available(iOS 18, macOS 15, watchOS 11, visionOS 2, *) { "wallet.bifold.fill" } else { "wallet.pass.fill" }
    }
}
