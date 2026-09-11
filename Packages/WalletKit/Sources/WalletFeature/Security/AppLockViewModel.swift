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
    /// Whether a passcode of the wallet's own stands behind the lock.
    @Published public private(set) var hasPasscode = false
    /// The lock is held by biometrics alone, with the device passcode as its only fallback.
    @Published public private(set) var isBiometricOnly = false
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
        hasPasscode = verifier != nil
        if let verifier { passcodeLength = verifier.length }
        // A passcode supersedes a biometric-only lock, so the two are never on at once.
        isBiometricOnly = !hasPasscode
            && preferences.bool(forKey: WalletPreferenceKeys.appLockBiometricsOnly)
        isEnabled = hasPasscode || isBiometricOnly
        if !isEnabled { isLocked = false }
    }

    /// Call when the app leaves the foreground so the grace period can be measured.
    ///
    /// A biometric prompt also resigns active, so one in progress is not treated as leaving.
    public func applicationDidResignActive() {
        guard isEnabled, !isLocked, !isAuthenticating else { return }
        lastActive = now()
    }

    /// Call when the app becomes active; locks if the grace period has elapsed.
    ///
    /// Without a timestamp there is no foreground absence to measure, so nothing is locked. That
    /// is the case the system biometric prompt creates: it resigns active while the app is still
    /// locked, and the app becomes active again the moment the prompt unlocks it. Reading that as
    /// a return from the background put the lock screen straight back up.
    public func applicationDidBecomeActive() {
        // Enrolling a face or finger, or withdrawing permission, happens in Settings while this app
        // is away, so re-read what the device offers rather than trust what it offered at launch.
        biometry = authenticator.availableBiometry()
        guard isEnabled, !isLocked, let lastActive else { return }
        if AppLockPolicy.shouldLock(lastActive: lastActive, now: now(), grace: gracePeriod) {
            isLocked = true
        }
        self.lastActive = nil
    }

    // MARK: - Unlocking

    public func authenticateWithBiometrics() async {
        guard isLocked, isEnabled, !isAuthenticating else { return }
        // Biometrics can be declined per-device when a wallet passcode stands behind them. With
        // nothing behind them they are the way in, so the prompt is always offered — and widened to
        // the device passcode, which still answers when a face or finger will not.
        if !isBiometricOnly {
            guard useBiometrics, biometry.isAvailable else { return }
        }
        guard updateLockout() == 0 else { return }
        isAuthenticating = true
        let success = await authenticator.authenticate(reason: "Unlock My Wallet",
                                                       allowingDevicePasscode: isBiometricOnly)
        isAuthenticating = false
        // A cancelled or failed prompt is not a passcode attempt, so it does not count as a failure.
        if success {
            unlock()
        } else if isBiometricOnly, !authenticator.canVerifyDeviceOwner() {
            // Nothing on the device can answer the prompt, so say so rather than leave a screen
            // whose only button does nothing.
            errorMessage = AppLockError.deviceOwnerUnavailable.localizedDescription
        }
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

    /// Locks the wallet with biometrics alone, without a passcode of its own.
    ///
    /// Verifying before turning it on proves the person enabling the lock can also get back
    /// through it, and refusing a device that cannot verify anyone avoids locking a wallet behind a
    /// prompt nothing can answer.
    public func enableBiometricLock() async throws {
        guard !hasPasscode else { return }
        guard authenticator.canVerifyDeviceOwner() else { throw AppLockError.deviceOwnerUnavailable }
        let reason = biometry.isAvailable
            ? "Lock My Wallet with \(biometry.title)"
            : "Lock My Wallet"
        guard await authenticator.authenticate(reason: reason, allowingDevicePasscode: true) else {
            throw AppLockError.notVerified
        }
        preferences.set(true, forKey: WalletPreferenceKeys.appLockBiometricsOnly)
        refreshState()
        isLocked = false
    }

    /// Turns a biometric-only lock off. Verified the same way it is unlocked, so a bystander
    /// holding an unlocked phone cannot quietly remove it.
    public func disableBiometricLock() async throws {
        guard isBiometricOnly else { return }
        guard await authenticator.authenticate(reason: "Turn off the lock on My Wallet",
                                               allowingDevicePasscode: true) else {
            throw AppLockError.notVerified
        }
        preferences.set(false, forKey: WalletPreferenceKeys.appLockBiometricsOnly)
        refreshState()
    }

    /// Sets or replaces the passcode. `confirmation` must match.
    public func setPasscode(_ passcode: String, confirmation: String, length: PasscodeLength) throws {
        try AppLockPolicy.validate(passcode, length: length)
        guard passcode == confirmation else { throw PasscodeError.mismatch }
        let verifier = try PasscodeHasher.makeVerifier(passcode: passcode, length: length)
        try store.save(verifier)
        passcodeLength = length
        // The passcode takes over from a biometric-only lock; biometrics keep unlocking it through
        // `useBiometrics`, now with the wallet's own passcode as the fallback.
        preferences.set(false, forKey: WalletPreferenceKeys.appLockBiometricsOnly)
        isBiometricOnly = false
        hasPasscode = true
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
        hasPasscode = false
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
