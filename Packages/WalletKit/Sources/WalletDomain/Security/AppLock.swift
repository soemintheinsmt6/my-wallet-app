import Foundation

/// How long the app may stay in the background before it locks again.
public enum AppLockGracePeriod: String, CaseIterable, Codable, Sendable, Identifiable {
    case immediately
    case oneMinute
    case fiveMinutes

    public var id: String { rawValue }

    public var interval: TimeInterval {
        switch self {
        case .immediately: 0
        case .oneMinute: 60
        case .fiveMinutes: 300
        }
    }

    public var title: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 minute"
        case .fiveMinutes: "After 5 minutes"
        }
    }
}

public enum PasscodeLength: Int, CaseIterable, Codable, Sendable, Identifiable {
    case four = 4
    case six = 6

    public var id: Int { rawValue }
    public var title: String { "\(rawValue) digits" }
}

public enum PasscodeError: LocalizedError, Equatable {
    case wrongLength(PasscodeLength)
    case notNumeric
    case mismatch
    case incorrect
    case lockedOut(retryAfter: TimeInterval)
    case storageFailed

    public var errorDescription: String? {
        switch self {
        case .wrongLength(let length): "Enter a \(length.rawValue)-digit passcode."
        case .notNumeric: "Passcodes use digits only."
        case .mismatch: "The passcodes did not match."
        case .incorrect: "Incorrect passcode."
        case .lockedOut(let retry):
            "Too many attempts. Try again in \(Int(retry.rounded(.up))) seconds."
        case .storageFailed: "The passcode could not be saved to the keychain."
        }
    }
}

/// Pure rules for when the app locks and how failed attempts are throttled.
///
/// Kept free of `LocalAuthentication` and the keychain so the decisions can be tested directly.
public enum AppLockPolicy {
    /// A fresh launch always locks; a returning app locks once the grace period has elapsed.
    ///
    /// A clock that moved backwards is treated as expired rather than trusted, so changing the
    /// device clock cannot extend an unlocked session.
    public static func shouldLock(lastActive: Date?, now: Date, grace: AppLockGracePeriod) -> Bool {
        guard let lastActive else { return true }
        if grace == .immediately { return true }
        let elapsed = now.timeIntervalSince(lastActive)
        guard elapsed >= 0 else { return true }
        return elapsed >= grace.interval
    }

    public static func validate(_ passcode: String, length: PasscodeLength) throws {
        guard passcode.allSatisfy(\.isASCII), passcode.allSatisfy(\.isNumber) else {
            throw PasscodeError.notNumeric
        }
        guard passcode.count == length.rawValue else { throw PasscodeError.wrongLength(length) }
    }

    /// Attempts are free until `freeAttempts`, then back off so a stolen device cannot be
    /// brute-forced through the app's own entry screen.
    public static let freeAttempts = 5

    public static func lockoutInterval(failedAttempts: Int) -> TimeInterval {
        guard failedAttempts > freeAttempts else { return 0 }
        let over = failedAttempts - freeAttempts
        // 30s, 60s, 120s, 240s … capped at 15 minutes.
        return min(900, 30 * pow(2, Double(over - 1)))
    }

    /// Seconds still to wait, or zero when another attempt is allowed.
    public static func remainingLockout(failedAttempts: Int, lastFailure: Date?, now: Date) -> TimeInterval {
        guard let lastFailure else { return 0 }
        let interval = lockoutInterval(failedAttempts: failedAttempts)
        guard interval > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(lastFailure)
        // Treat a backwards clock as no time served.
        guard elapsed >= 0 else { return interval }
        return max(0, interval - elapsed)
    }
}
