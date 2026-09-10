import CryptoKit
import Foundation
import Security
import WalletDomain

/// A stored passcode verifier: a random salt and the hash it produced.
///
/// The passcode itself is never stored or written to disk in any recoverable form.
public struct PasscodeVerifier: Codable, Sendable, Equatable {
    public let salt: Data
    public let hash: Data
    public let length: PasscodeLength

    public init(salt: Data, hash: Data, length: PasscodeLength) {
        self.salt = salt
        self.hash = hash
        self.length = length
    }
}

public protocol PasscodeStoring: Sendable {
    func load() throws -> PasscodeVerifier?
    func save(_ verifier: PasscodeVerifier) throws
    func clear() throws
}

/// Hashing and verification shared by every store.
///
/// A 4- or 6-digit passcode has a small keyspace, so the verifier's real protection is the
/// keychain item's device-only, when-unlocked accessibility plus the attempt throttling in
/// `AppLockPolicy`. Salting stops a precomputed table from covering every device at once.
public enum PasscodeHasher {
    public static func makeVerifier(passcode: String, length: PasscodeLength) throws -> PasscodeVerifier {
        try AppLockPolicy.validate(passcode, length: length)
        var salt = Data(count: 32)
        let status = salt.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
        }
        guard status == errSecSuccess else { throw PasscodeError.storageFailed }
        return PasscodeVerifier(salt: salt, hash: hash(passcode: passcode, salt: salt), length: length)
    }

    public static func matches(passcode: String, verifier: PasscodeVerifier) -> Bool {
        let candidate = hash(passcode: passcode, salt: verifier.salt)
        // Constant-time comparison; `Data ==` would exit at the first differing byte.
        guard candidate.count == verifier.hash.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(candidate, verifier.hash) { difference |= left ^ right }
        return difference == 0
    }

    private static func hash(passcode: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(passcode.utf8))
        return Data(SHA256.hash(data: input))
    }
}

/// Keychain-backed storage for the passcode verifier.
///
/// The item is `ThisDeviceOnly` so it never travels to a backup or another device, and
/// `WhenUnlocked` so a locked device cannot be probed in the background.
public struct KeychainPasscodeStore: PasscodeStoring {
    private let service: String
    private let account: String

    public init(service: String = "com.app.My-Wallet.applock", account: String = "passcode") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() throws -> PasscodeVerifier? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw PasscodeError.storageFailed }
        return try? JSONDecoder().decode(PasscodeVerifier.self, from: data)
    }

    public func save(_ verifier: PasscodeVerifier) throws {
        let data = try JSONEncoder().encode(verifier)
        // Replace rather than update, so a corrupt or differently-shaped item cannot linger.
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw PasscodeError.storageFailed }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PasscodeError.storageFailed
        }
    }
}
