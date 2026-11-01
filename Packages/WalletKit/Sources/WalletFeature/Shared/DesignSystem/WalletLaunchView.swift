import SwiftUI

/// What the app shows while it opens: the wallet mark, the app's name and a quiet progress line.
///
/// Used both while storage opens and while the dashboard's first load runs, on the dashboard's own
/// background, so launch reads as one continuous screen rather than a spinner, a color change and
/// a second spinner.
public struct WalletLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    public init() {}

    public var body: some View {
        VStack(spacing: WalletMetrics.large) {
            Image(systemName: "wallet.bifold.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(Color.accentColor.gradient,
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.3), radius: 16, y: 8)
                // A slow breath says "working" without a spinner competing for attention;
                // still when the user asks for reduced motion.
                .scaleEffect(breathing ? 1.04 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                           value: breathing)
                .accessibilityHidden(true)

            Text("My Wallet")
                .font(.title2.weight(.bold))

            HStack(spacing: WalletMetrics.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Opening your wallet…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.walletGroupedBackground.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opening your wallet")
        .onAppear { breathing = true }
    }
}

#Preview {
    WalletLaunchView()
}
