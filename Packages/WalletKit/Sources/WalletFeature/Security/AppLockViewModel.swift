import Combine
import Foundation
import WalletDomain

/// Owns whether the app is locked, and everything needed to unlock or reconfigure it.
///
/// Lock settings live in `UserDefaults`; only the passcode verifier goes to the keychain. Failed
/// attempts are tracked here and throttled by `AppLockPolicy` so the entry screen cannot be used
/// to brute-force a short passcode.
@MainActor
public final class AppLockViewModel: ObservableObject {
    @Published public private(set) var isLocked = false
    @Published public private(set) var isEnabled = false
    @Published public private(set) var biometry = BiometryKind.none
    @Published public var useBiometrics = true {
        didSet {
            guard useBiometrics != oldValue else { return }
            preferences.set(useBiometrics, forKey: WalletPreferenceKeys.appLockUseBiometrics)
        }
    }
    @Published public var gracePeriod = AppLockGracePeriod.immediately {
        didSet {
            guard gracePeriod != oldValue else { return }
            preferences.set(gracePeriod.rawValue, forKey: WalletPreferenceKeys.appLockGracePeriod)
        }
    }
    @Published public private(set) var passcodeLength = PasscodeLength.six
    @Published public private(set) var failedAttempts = 0
    @Published public private(set) var remainingLockout: TimeInterval = 0
    @Published public var errorMessage: String?
    /// True while a biometric prompt is on screen, so the lock screen can hide its keypad.
    @Published public private(set) var isAuthenticating = false

    private let store: any PasscodeStoring
    private let authenticator: any BiometricAuthenticating
    private let preferences: UserDefaults
    private let now: () -> Date
    private var lastActive: Date?
    private var lastFailure: Date?
    private var countdown: Task<Void, Never>?

    public init(store: any PasscodeStoring = KeychainPasscodeStore(),
                authenticator: any BiometricAuthenticating = LocalAuthenticationAuthenticator(),
                preferences: UserDefaults = .standard,
                now: @escaping () -> Date = Date.init) {
        self.store = store
        self.authenticator = authenticator
        self.preferences = preferences
        self.now = now
        useBiometrics = preferences.object(forKey: WalletPreferenceKeys.appLockUseBiometrics) as? Bool ?? true
        gracePeriod = (preferences.string(forKey: WalletPreferenceKeys.appLockGracePeriod)
            .flatMap(AppLockGracePeriod.init(rawValue:))) ?? .immediately
        refreshState()
    }

    // MARK: - Lifecycle

    /// Reads the stored verifier and locks immediately when app lock is on.
    public func start() {
        refreshState()
        if isEnabled { isLocked = true }
    }

    private func refreshState() {
        biometry = authenticator.availableBiometry()
        let verifier = try? store.load()
        isEnabled = verifier != nil
        if let verifier { passcodeLength = verifier.length }
        if !isEnabled { isLocked = false }
    }

    /// Call when the app leaves the foreground so the grace period can be measured.
    public func applicationDidResignActive() {
        guard isEnabled, !isLocked else { return }
        lastActive = now()
    }

    /// Call when the app becomes active; locks if the grace period has elapsed.
    public func applicationDidBecomeActive() {
        guard isEnabled, !isLocked else { return }
        if AppLockPolicy.shouldLock(lastActive: lastActive, now: now(), grace: gracePeriod) {
            isLocked = true
        }
    }

    public func lockNow() {
        guard isEnabled else { return }
        isLocked = true
    }

    // MARK: - Unlocking

    public func authenticateWithBiometrics() async {
        guard isLocked, isEnabled, useBiometrics, biometry.isAvailable, !isAuthenticating else { return }
        guard updateLockout() == 0 else { return }
        isAuthenticating = true
        let success = await authenticator.authenticate(reason: "Unlock My Wallet")
        isAuthenticating = false
        // A cancelled or failed prompt is not a passcode attempt, so it does not count as a failure.
        if success { unlock() }
    }

    /// Returns `true` when the passcode was accepted.
    @discardableResult
    public func submit(passcode: String) -> Bool {
        guard isLocked, let verifier = try? store.load() else { return false }
        guard updateLockout() == 0 else {
            errorMessage = PasscodeError.lockedOut(retryAfter: remainingLockout).localizedDescription
            return false
        }
        guard PasscodeHasher.matches(passcode: passcode, verifier: verifier) else {
            failedAttempts += 1
            lastFailure = now()
            updateLockout()
            errorMessage = remainingLockout > 0
                ? PasscodeError.lockedOut(retryAfter: remainingLockout).localizedDescription
                : PasscodeError.incorrect.localizedDescription
            return false
        }
        unlock()
        return true
    }

    private func unlock() {
        isLocked = false
        failedAttempts = 0
        lastFailure = nil
        remainingLockout = 0
        errorMessage = nil
        lastActive = nil
        countdown?.cancel()
        countdown = nil
    }

    @discardableResult
    private func updateLockout() -> TimeInterval {
        remainingLockout = AppLockPolicy.remainingLockout(failedAttempts: failedAttempts,
                                                          lastFailure: lastFailure, now: now())
        if remainingLockout > 0, countdown == nil { startCountdown() }
        return remainingLockout
    }

    /// Ticks the visible lockout countdown down to zero, then clears the message.
    private func startCountdown() {
        countdown?.cancel()
        countdown = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let remaining = AppLockPolicy.remainingLockout(failedAttempts: failedAttempts,
                                                               lastFailure: lastFailure, now: now())
                remainingLockout = remaining
                guard remaining <= 0 else { continue }
                errorMessage = nil
                countdown = nil
                return
            }
        }
    }

    // MARK: - Configuration

    /// Sets or replaces the passcode. `confirmation` must match.
    public func setPasscode(_ passcode: String, confirmation: String, length: PasscodeLength) throws {
        try AppLockPolicy.validate(passcode, length: length)
        guard passcode == confirmation else { throw PasscodeError.mismatch }
        let verifier = try PasscodeHasher.makeVerifier(passcode: passcode, length: length)
        try store.save(verifier)
        passcodeLength = length
        isEnabled = true
        isLocked = false
        failedAttempts = 0
        lastFailure = nil
        remainingLockout = 0
    }

    /// Turns app lock off. Requires the current passcode so a bystander cannot disable it.
    public func disableLock(currentPasscode: String) throws {
        guard let verifier = try? store.load() else { return }
        guard PasscodeHasher.matches(passcode: currentPasscode, verifier: verifier) else {
            throw PasscodeError.incorrect
        }
        try store.clear()
        isEnabled = false
        isLocked = false
        failedAttempts = 0
        lastFailure = nil
        remainingLockout = 0
    }

    public func verify(currentPasscode: String) -> Bool {
        guard let verifier = try? store.load() else { return false }
        return PasscodeHasher.matches(passcode: currentPasscode, verifier: verifier)
    }
}
