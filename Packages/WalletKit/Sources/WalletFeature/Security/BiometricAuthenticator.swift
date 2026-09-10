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
    /// Returns `true` on success. Cancellation and fallback return `false` rather than throwing,
    /// so the caller simply keeps showing the passcode entry.
    func authenticate(reason: String) async -> Bool
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

    public func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        // The app has its own passcode fallback, so suppress the system's.
        context.localizedFallbackTitle = ""
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                    localizedReason: reason)
        } catch {
            return false
        }
    }
}
