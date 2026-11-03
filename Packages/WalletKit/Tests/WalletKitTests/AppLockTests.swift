import Foundation
import Testing
import WalletDomain
@testable import WalletFeature

/// In-memory replacements for the keychain and LocalAuthentication.
private final class MemoryPasscodeStore: PasscodeStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var verifier: PasscodeVerifier?
    var failWrites = false

    init(verifier: PasscodeVerifier? = nil) { self.verifier = verifier }

    func load() throws -> PasscodeVerifier? {
        lock.withLock { verifier }
    }

    func save(_ value: PasscodeVerifier) throws {
        if failWrites { throw PasscodeError.storageFailed }
        lock.withLock { verifier = value }
    }

    func clear() throws {
        lock.withLock { verifier = nil }
    }
}

private final class StubAuthenticator: BiometricAuthenticating, @unchecked Sendable {
    private let lock = NSLock()
    private let kind: BiometryKind
    private let succeeds: Bool
    private let verifiesDeviceOwner: Bool
    private var allowedDevicePasscode: Bool?

    init(kind: BiometryKind = .faceID, succeeds: Bool = true, verifiesDeviceOwner: Bool = true) {
        self.kind = kind
        self.succeeds = succeeds
        self.verifiesDeviceOwner = verifiesDeviceOwner
    }

    /// What the last prompt was willing to accept, so tests can tell a biometrics-only unlock
    /// (which must fall back to the device passcode) from one backed by a wallet passcode.
    var lastAllowedDevicePasscode: Bool? { lock.withLock { allowedDevicePasscode } }

    func availableBiometry() -> BiometryKind { kind }
    func canVerifyDeviceOwner() -> Bool { verifiesDeviceOwner }

    func authenticate(reason: String, allowingDevicePasscode: Bool) async -> Bool {
        lock.withLock { allowedDevicePasscode = allowingDevicePasscode }
        return succeeds
    }
}

struct AppLockPolicyTests {
    private let start = Date(timeIntervalSince1970: 1_704_110_400)

    @Test func aFreshLaunchAlwaysLocks() {
        for grace in AppLockGracePeriod.allCases {
            #expect(AppLockPolicy.shouldLock(lastActive: nil, now: start, grace: grace))
        }
    }

    @Test func gracePeriodLocksOnlyAfterItElapses() {
        #expect(AppLockPolicy.shouldLock(lastActive: start, now: start, grace: .immediately))

        // One minute: 59s still open, 60s locks.
        #expect(!AppLockPolicy.shouldLock(lastActive: start, now: start.addingTimeInterval(59), grace: .oneMinute))
        #expect(AppLockPolicy.shouldLock(lastActive: start, now: start.addingTimeInterval(60), grace: .oneMinute))

        #expect(!AppLockPolicy.shouldLock(lastActive: start, now: start.addingTimeInterval(299), grace: .fiveMinutes))
        #expect(AppLockPolicy.shouldLock(lastActive: start, now: start.addingTimeInterval(300), grace: .fiveMinutes))
    }

    /// Winding the clock back must not extend an unlocked session.
    @Test func aBackwardsClockLocks() {
        #expect(AppLockPolicy.shouldLock(lastActive: start, now: start.addingTimeInterval(-600), grace: .fiveMinutes))
    }

    @Test func passcodeValidationRejectsLengthAndNonDigits() {
        #expect(throws: Never.self) { try AppLockPolicy.validate("1234", length: .four) }
        #expect(throws: Never.self) { try AppLockPolicy.validate("123456", length: .six) }
        #expect(throws: PasscodeError.wrongLength(.four)) { try AppLockPolicy.validate("12345", length: .four) }
        #expect(throws: PasscodeError.notNumeric) { try AppLockPolicy.validate("12a4", length: .four) }
        // Non-ASCII digits must not slip through `isNumber`.
        #expect(throws: PasscodeError.notNumeric) { try AppLockPolicy.validate("١٢٣٤", length: .four) }
    }

    @Test func lockoutBacksOffAfterFreeAttemptsAndIsCapped() {
        #expect(AppLockPolicy.lockoutInterval(failedAttempts: 5) == 0)
        #expect(AppLockPolicy.lockoutInterval(failedAttempts: 6) == 30)
        #expect(AppLockPolicy.lockoutInterval(failedAttempts: 7) == 60)
        #expect(AppLockPolicy.lockoutInterval(failedAttempts: 8) == 120)
        #expect(AppLockPolicy.lockoutInterval(failedAttempts: 40) == 900)
    }

    @Test func remainingLockoutCountsDownAndIgnoresBackwardsClocks() {
        #expect(AppLockPolicy.remainingLockout(failedAttempts: 6, lastFailure: start,
                                               now: start.addingTimeInterval(10)) == 20)
        #expect(AppLockPolicy.remainingLockout(failedAttempts: 6, lastFailure: start,
                                               now: start.addingTimeInterval(30)) == 0)
        #expect(AppLockPolicy.remainingLockout(failedAttempts: 3, lastFailure: start, now: start) == 0)
        #expect(AppLockPolicy.remainingLockout(failedAttempts: 6, lastFailure: start,
                                               now: start.addingTimeInterval(-5)) == 30)
    }
}

struct PasscodeHasherTests {
    @Test func verifierMatchesOnlyTheOriginalPasscode() throws {
        let verifier = try PasscodeHasher.makeVerifier(passcode: "1234", length: .four)
        #expect(PasscodeHasher.matches(passcode: "1234", verifier: verifier))
        #expect(!PasscodeHasher.matches(passcode: "4321", verifier: verifier))
        #expect(!PasscodeHasher.matches(passcode: "123456", verifier: verifier))
    }

    /// A distinct salt per device stops one precomputed table covering every install.
    @Test func eachVerifierUsesAFreshSaltAndStoresNoPasscode() throws {
        let first = try PasscodeHasher.makeVerifier(passcode: "1234", length: .four)
        let second = try PasscodeHasher.makeVerifier(passcode: "1234", length: .four)
        #expect(first.salt != second.salt)
        #expect(first.hash != second.hash)
        #expect(first.salt.count == 32)

        let encoded = try JSONEncoder().encode(first)
        // A strict decode, so invalid bytes fail the test rather than hide the number.
        #expect(try !#require(String(data: encoded, encoding: .utf8)).contains("1234"))
    }

    @Test func makingAVerifierRejectsAnInvalidPasscode() {
        #expect(throws: PasscodeError.wrongLength(.six)) {
            try PasscodeHasher.makeVerifier(passcode: "1234", length: .six)
        }
    }
}

@MainActor
struct AppLockViewModelTests {
    private func model(passcode: String? = nil, length: PasscodeLength = .four,
                       authenticator: StubAuthenticator = StubAuthenticator(),
                       biometricsOnly: Bool = false,
                       now: @escaping () -> Date = Date.init) throws -> (AppLockViewModel, MemoryPasscodeStore) {
        let store = MemoryPasscodeStore()
        if let passcode {
            try store.save(PasscodeHasher.makeVerifier(passcode: passcode, length: length))
        }
        let defaults = UserDefaults(suiteName: "applock.tests.\(UUID().uuidString)")!
        // Stands in for a lock enabled on a previous launch.
        if biometricsOnly { defaults.set(true, forKey: WalletPreferenceKeys.appLockBiometricsOnly) }
        let model = AppLockViewModel(store: store, authenticator: authenticator,
                                     preferences: defaults, now: now)
        return (model, store)
    }

    @Test func lockIsOffUntilAPasscodeExists() throws {
        let (model, _) = try model()
        model.start()
        #expect(!model.isEnabled)
        #expect(!model.isLocked)
    }

    @Test func startingWithAPasscodeLocksImmediately() throws {
        let (model, _) = try model(passcode: "1234")
        model.start()
        #expect(model.isEnabled)
        #expect(model.isLocked)
        #expect(model.passcodeLength == .four)
    }

    @Test func correctPasscodeUnlocksAndClearsFailures() throws {
        let (model, _) = try model(passcode: "1234")
        model.start()

        #expect(!model.submit(passcode: "0000"))
        #expect(model.failedAttempts == 1)
        #expect(model.isLocked)

        #expect(model.submit(passcode: "1234"))
        #expect(!model.isLocked)
        #expect(model.failedAttempts == 0)
        #expect(model.errorMessage == nil)
    }

    @Test func repeatedFailuresTriggerAThrottleThatBlocksFurtherAttempts() throws {
        var clock = Date(timeIntervalSince1970: 1_704_110_400)
        let (model, _) = try model(passcode: "1234", now: { clock })
        model.start()

        for _ in 0..<AppLockPolicy.freeAttempts { _ = model.submit(passcode: "0000") }
        #expect(model.remainingLockout == 0)

        _ = model.submit(passcode: "0000")
        #expect(model.remainingLockout == 30)

        // Even the right passcode is refused while throttled.
        #expect(!model.submit(passcode: "1234"))
        #expect(model.isLocked)

        // Once the delay has been served, it is accepted again.
        clock = clock.addingTimeInterval(30)
        #expect(model.submit(passcode: "1234"))
        #expect(!model.isLocked)
    }

    @Test func biometricSuccessUnlocksAndFailureLeavesItLocked() async throws {
        let (unlocking, _) = try model(passcode: "1234", authenticator: StubAuthenticator(succeeds: true))
        unlocking.start()
        await unlocking.authenticateWithBiometrics()
        #expect(!unlocking.isLocked)

        let (refusing, _) = try model(passcode: "1234", authenticator: StubAuthenticator(succeeds: false))
        refusing.start()
        await refusing.authenticateWithBiometrics()
        #expect(refusing.isLocked)
        // A cancelled prompt is not a passcode attempt and must not count toward the throttle.
        #expect(refusing.failedAttempts == 0)
    }

    /// The system biometric prompt takes the app out of the active phase, so a successful unlock is
    /// immediately followed by a return to active. That must not be read as coming back from the
    /// background, or the lock screen reappears the instant Face ID dismisses it.
    @Test func unlockingWithBiometricsSurvivesTheScenePhaseTheirPromptCauses() async throws {
        let (model, _) = try model(passcode: "1234", authenticator: StubAuthenticator(succeeds: true))
        model.start()

        // The prompt appears: the app resigns active while still locked.
        model.applicationDidResignActive()
        await model.authenticateWithBiometrics()
        #expect(!model.isLocked)

        // The prompt dismisses and the app becomes active again.
        model.applicationDidBecomeActive()
        #expect(!model.isLocked)
    }

    // MARK: - Biometrics without a wallet passcode

    @Test func biometricsCanHoldTheLockWithNoPasscodeBehindThem() async throws {
        let authenticator = StubAuthenticator(succeeds: true)
        let (model, store) = try model(authenticator: authenticator)
        #expect(!model.isEnabled)

        try await model.enableBiometricLock()
        #expect(model.isEnabled)
        #expect(model.isBiometricOnly)
        #expect(!model.hasPasscode)
        #expect(try store.load() == nil)

        model.start()
        #expect(model.isLocked)
        await model.authenticateWithBiometrics()
        #expect(!model.isLocked)
        // Nothing else can let the owner in, so the prompt must accept the device passcode too.
        #expect(authenticator.lastAllowedDevicePasscode == true)
    }

    /// A prompt backed by a wallet passcode stays on biometrics, so a refusal falls through to the
    /// keypad instead of the device passcode.
    @Test func aWalletPasscodeKeepsThePromptOnBiometricsAlone() async throws {
        let authenticator = StubAuthenticator(succeeds: true)
        let (model, _) = try model(passcode: "1234", authenticator: authenticator)
        model.start()
        await model.authenticateWithBiometrics()
        #expect(authenticator.lastAllowedDevicePasscode == false)
    }

    @Test func aDeviceThatCannotVerifyAnyoneRefusesABiometricLock() async throws {
        let (model, _) = try model(authenticator: StubAuthenticator(verifiesDeviceOwner: false))
        await #expect(throws: AppLockError.deviceOwnerUnavailable) {
            try await model.enableBiometricLock()
        }
        #expect(!model.isEnabled)
    }

    @Test func anUnverifiedAttemptLeavesTheBiometricLockAsItWas() async throws {
        let (model, _) = try model(authenticator: StubAuthenticator(succeeds: false))
        await #expect(throws: AppLockError.notVerified) {
            try await model.enableBiometricLock()
        }
        #expect(!model.isEnabled)
        #expect(!model.isBiometricOnly)
    }

    @Test func turningTheBiometricLockOffRequiresVerifying() async throws {
        let (enabled, _) = try model(authenticator: StubAuthenticator(succeeds: true))
        try await enabled.enableBiometricLock()
        try await enabled.disableBiometricLock()
        #expect(!enabled.isEnabled)
        #expect(!enabled.isBiometricOnly)

        // A refused prompt must leave the lock standing.
        let (refused, _) = try model(authenticator: StubAuthenticator(succeeds: false),
                                     biometricsOnly: true)
        #expect(refused.isBiometricOnly)
        await #expect(throws: AppLockError.notVerified) { try await refused.disableBiometricLock() }
        #expect(refused.isBiometricOnly)
    }

    @Test func aPasscodeSupersedesABiometricOnlyLock() async throws {
        let (model, _) = try model(authenticator: StubAuthenticator(succeeds: true))
        try await model.enableBiometricLock()

        try model.setPasscode("1234", confirmation: "1234", length: .four)
        #expect(model.hasPasscode)
        #expect(!model.isBiometricOnly)
        #expect(model.isEnabled)

        // Removing the passcode leaves no lock behind, rather than silently reverting to one.
        try model.disableLock(currentPasscode: "1234")
        #expect(!model.isEnabled)
        #expect(!model.isBiometricOnly)
    }

    @Test func biometricsAreSkippedWhenUnavailableOrTurnedOff() async throws {
        let (noHardware, _) = try model(passcode: "1234",
                                        authenticator: StubAuthenticator(kind: .none, succeeds: true))
        noHardware.start()
        await noHardware.authenticateWithBiometrics()
        #expect(noHardware.isLocked)

        let (optedOut, _) = try model(passcode: "1234", authenticator: StubAuthenticator(succeeds: true))
        optedOut.start()
        optedOut.useBiometrics = false
        await optedOut.authenticateWithBiometrics()
        #expect(optedOut.isLocked)
    }

    @Test func backgroundingLocksOnlyOnceTheGracePeriodElapses() throws {
        var clock = Date(timeIntervalSince1970: 1_704_110_400)
        let (model, _) = try model(passcode: "1234", now: { clock })
        model.start()
        #expect(model.submit(passcode: "1234"))

        model.gracePeriod = .oneMinute
        model.applicationDidResignActive()
        clock = clock.addingTimeInterval(30)
        model.applicationDidBecomeActive()
        #expect(!model.isLocked)

        model.applicationDidResignActive()
        clock = clock.addingTimeInterval(90)
        model.applicationDidBecomeActive()
        #expect(model.isLocked)
    }

    @Test func settingAPasscodeRequiresAMatchingConfirmation() throws {
        let (model, store) = try model()
        #expect(throws: PasscodeError.mismatch) {
            try model.setPasscode("1234", confirmation: "4321", length: .four)
        }
        #expect(try store.load() == nil)

        try model.setPasscode("123456", confirmation: "123456", length: .six)
        #expect(model.isEnabled)
        #expect(model.passcodeLength == .six)
        #expect(try store.load() != nil)
    }

    @Test func disablingTheLockRequiresTheCurrentPasscode() throws {
        let (model, store) = try model(passcode: "1234")
        model.start()

        #expect(throws: PasscodeError.incorrect) { try model.disableLock(currentPasscode: "9999") }
        #expect(model.isEnabled)
        #expect(try store.load() != nil)

        try model.disableLock(currentPasscode: "1234")
        #expect(!model.isEnabled)
        #expect(!model.isLocked)
        #expect(try store.load() == nil)
    }
}
