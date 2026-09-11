import SwiftUI
import WalletDomain

/// The screen shown over the app while it is locked.
///
/// Covers the whole window so no balance is readable behind it, and offers biometrics first with
/// the passcode keypad always available as the fallback.
public struct AppLockView: View {
    @ObservedObject private var viewModel: AppLockViewModel
    @State private var entry = ""
    @State private var shake = 0

    public init(viewModel: AppLockViewModel) { self.viewModel = viewModel }

    private var isLockedOut: Bool { viewModel.remainingLockout > 0 }

    public var body: some View {
        VStack(spacing: WalletMetrics.xLarge) {
            Spacer(minLength: 0)

            VStack(spacing: WalletMetrics.medium) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                Text("My Wallet is Locked")
                    .font(.title3.weight(.semibold))
                Text(prompt)
                    .font(.footnote)
                    .foregroundStyle(isLockedOut ? .red : .secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.identity)
            }

            if !viewModel.isBiometricOnly {
                PasscodeDots(entered: entry.count, length: viewModel.passcodeLength.rawValue)
                    .modifier(ShakeEffect(travel: CGFloat(shake)))
            }

            if let message = viewModel.errorMessage, !isLockedOut {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            if viewModel.isBiometricOnly {
                // Nothing to type: the only way through is the device's own verification, which is
                // offered on appearance and repeatable here if it was dismissed.
                Button {
                    Task { await viewModel.authenticateWithBiometrics() }
                } label: {
                    Label("Unlock with \(unlockTitle)", systemImage: viewModel.biometry.symbol)
                        .font(.body.weight(.medium))
                        .frame(minHeight: WalletMetrics.touchTarget)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isAuthenticating)
            } else {
                PasscodeKeypad(onDigit: append, onDelete: deleteLast,
                               biometry: viewModel.useBiometrics ? viewModel.biometry : .none,
                               onBiometry: { Task { await viewModel.authenticateWithBiometrics() } },
                               isDisabled: isLockedOut || viewModel.isAuthenticating)
            }

            Spacer(minLength: 0)
        }
        .padding(WalletMetrics.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        // Biometrics are offered on appearance so an enrolled user rarely types anything.
        .task { await viewModel.authenticateWithBiometrics() }
    }

    private var lockoutText: String {
        "Too many attempts. Try again in \(Int(viewModel.remainingLockout.rounded(.up)))s."
    }

    /// Named for the sensor where there is one, and for the device passcode where there is not —
    /// which is all a biometric-only lock has left once a face or finger stops being recognized.
    private var unlockTitle: String {
        viewModel.biometry.isAvailable ? viewModel.biometry.title : "Device Passcode"
    }

    private var prompt: String {
        if isLockedOut { return lockoutText }
        return viewModel.isBiometricOnly
            ? "Unlock with \(unlockTitle) to continue."
            : "Enter your passcode to continue."
    }

    private func append(_ digit: String) {
        guard !isLockedOut, entry.count < viewModel.passcodeLength.rawValue else { return }
        entry.append(digit)
        viewModel.errorMessage = nil
        guard entry.count == viewModel.passcodeLength.rawValue else { return }
        let attempt = entry
        // Clear immediately so the dots reset whether or not the attempt succeeds.
        entry = ""
        if !viewModel.submit(passcode: attempt) {
            withAnimation(.default) { shake += 1 }
        }
    }

    private func deleteLast() {
        guard !entry.isEmpty else { return }
        entry.removeLast()
    }
}

/// Nudges the passcode dots sideways after a wrong entry.
///
/// Driven by the failure count rather than a boolean, so repeated failures each animate. Honors
/// Reduce Motion by collapsing to no movement.
private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard !reduceMotion else { return ProjectionTransform(.identity) }
        let offset = 10 * sin(travel * .pi * 3)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

/// Wraps the app so locked content is never rendered behind the lock screen.
public struct AppLockGate<Content: View>: View {
    @ObservedObject private var viewModel: AppLockViewModel
    @Environment(\.scenePhase) private var scenePhase
    private let content: () -> Content

    public init(viewModel: AppLockViewModel, @ViewBuilder content: @escaping () -> Content) {
        self.viewModel = viewModel
        self.content = content
    }

    public var body: some View {
        ZStack {
            if !viewModel.isLocked { content() }
            if viewModel.isLocked {
                AppLockView(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: viewModel.isLocked)
        .task { viewModel.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            // `.inactive` covers the app switcher, where the snapshot iOS takes must not show data.
            case .inactive, .background: viewModel.applicationDidResignActive()
            case .active: viewModel.applicationDidBecomeActive()
            @unknown default: break
            }
        }
    }
}
