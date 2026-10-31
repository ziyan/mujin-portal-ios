#if canImport(Security)
    import Foundation
    import Security

    /// Keychain keeps the app's secrets on this phone. Items go in the first
    /// keychain group of the app's entitlements, which the notification
    /// extension shares, and can be read once the phone has been unlocked after
    /// starting. They are never copied to another phone.
    public enum Keychain {
        static let service = "com.ziyan.mujinportal.accounts"

        static func query(_ name: String) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: name,
            ]
        }

        public static func read(_ name: String) throws -> Data? {
            var reading = query(name)
            reading[kSecReturnData as String] = true
            reading[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(reading as CFDictionary, &item)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
            return data
        }

        public static func write(_ data: Data, as name: String) throws {
            let status = SecItemUpdate(query(name) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var adding = query(name)
                adding[kSecValueData as String] = data
                adding[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                let added = SecItemAdd(adding as CFDictionary, nil)
                guard added == errSecSuccess else { throw KeychainError(status: added) }
            } else if status != errSecSuccess {
                throw KeychainError(status: status)
            }
        }

        public static func delete(_ name: String) throws {
            let status = SecItemDelete(query(name) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
        }
    }

    /// KeychainError is the keychain refusing, with its status code.
    public struct KeychainError: Error {
        public let status: OSStatus
    }

    /// KeychainAccountStore keeps the account ring in the keychain.
    public struct KeychainAccountStore: AccountStore {
        static let name = "account-ring"

        public init() {}

        public func loadRing() throws -> AccountRing {
            guard let data = try Keychain.read(Self.name) else { return AccountRing() }
            return try JSONDecoder().decode(AccountRing.self, from: data)
        }

        public func saveRing(_ ring: AccountRing) throws {
            try Keychain.write(JSONEncoder().encode(ring), as: Self.name)
        }
    }
#endif
