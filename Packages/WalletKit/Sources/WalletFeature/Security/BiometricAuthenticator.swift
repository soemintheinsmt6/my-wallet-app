import Foundation
import LocalAuthentication

public enum BiometryKind: Sendable, Equatable {
    case none
    case touchID
    case faceID
    case opticID

    public var title: String {
        switch self {
        case .none: "Biometrics"
        case .touchID: "Touch ID"
        case .faceID: "Face ID"
        case .opticID: "Optic ID"
        }
    }

    public var symbol: String {
        switch self {
        case .none: "lock"
        case .touchID: "touchid"
        case .faceID: "faceid"
        case .opticID: "opticid"
        }
    }

    public var isAvailable: Bool { self != .none }
}

public protocol BiometricAuthenticating: Sendable {
    /// What this device offers right now, or `.none` when biometrics are unavailable or unenrolled.
    func availableBiometry() -> BiometryKind
    /// Whether the device can verify its owner at all — by biometrics, or failing those by its own
    /// passcode. False on a device with no passcode set, where there is nothing to verify against.
    func canVerifyDeviceOwner() -> Bool
    /// Returns `true` on success. Cancellation and fallback return `false` rather than throwing,
    /// so the caller simply keeps showing the passcode entry.
    ///
    /// `allowingDevicePasscode` widens the check to the device passcode. That is what keeps a
    /// wallet locked by biometrics alone reachable when a face or finger will not verify, and it
    /// is why biometrics can stand on their own without a wallet passcode behind them.
    func authenticate(reason: String, allowingDevicePasscode: Bool) async -> Bool
}

public struct LocalAuthenticationAuthenticator: BiometricAuthenticating {
    public init() {}

    public func availableBiometry() -> BiometryKind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .touchID: return .touchID
        case .faceID: return .faceID
        case .opticID: return .opticID
        default: return .none
        }
    }

    public func canVerifyDeviceOwner() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    public func authenticate(reason: String, allowingDevicePasscode: Bool) async -> Bool {
        let context = LAContext()
        if !allowingDevicePasscode {
            // A wallet passcode stands behind this prompt, so suppress the system's own fallback.
            context.localizedFallbackTitle = ""
        }
        do {
            return try await context.evaluatePolicy(
                allowingDevicePasscode ? .deviceOwnerAuthentication : .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason)
        } catch {
            return false
        }
    }
}
