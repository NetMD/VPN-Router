import Foundation
import Security

struct KeychainSecretStore: Sendable {
    private let service: String
    private let accessGroup: String?

    init(
        service: String = "VPNRouter.WireGuardPrivateKeys",
        accessGroup: String? = KeychainEntitlements.defaultAccessGroup()
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    nonisolated func savePrivateKey(_ privateKey: String, profileId: UUID) throws {
        guard let privateKeyData = privateKey.data(using: .utf8) else {
            throw KeychainSecretStoreError.invalidSecretEncoding
        }

        var addQuery = baseQuery(profileId: profileId)
        addQuery[kSecValueData as String] = privateKeyData
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }

        guard addStatus == errSecDuplicateItem else {
            throw KeychainSecretStoreError.unexpectedStatus(addStatus)
        }

        let updateAttributes: [String: Any] = [
            kSecValueData as String: privateKeyData
        ]
        let updateStatus = SecItemUpdate(baseQuery(profileId: profileId) as CFDictionary, updateAttributes as CFDictionary)
        guard updateStatus == errSecSuccess else {
            throw KeychainSecretStoreError.unexpectedStatus(updateStatus)
        }
    }

    nonisolated func loadPrivateKey(profileId: UUID) throws -> String? {
        var query = baseQuery(profileId: profileId)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainSecretStoreError.unexpectedStatus(status)
        }

        guard
            let data = result as? Data,
            let privateKey = String(data: data, encoding: .utf8)
        else {
            throw KeychainSecretStoreError.invalidSecretEncoding
        }

        return privateKey
    }

    nonisolated func deletePrivateKey(profileId: UUID) throws {
        let status = SecItemDelete(baseQuery(profileId: profileId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.unexpectedStatus(status)
        }
    }

    private nonisolated func baseQuery(profileId: UUID) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: profileId),
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    private nonisolated func account(for profileId: UUID) -> String {
        "wireguard.privateKey.\(profileId.uuidString)"
    }
}

enum KeychainEntitlements {
    nonisolated static func defaultAccessGroup() -> String? {
        guard
            let task = SecTaskCreateFromSelf(nil),
            let value = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil),
            let groups = value as? [String]
        else {
            return nil
        }

        return groups.first
    }
}

enum KeychainSecretStoreError: LocalizedError, Equatable {
    case invalidSecretEncoding
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidSecretEncoding:
            return "Secret could not be encoded or decoded as UTF-8."
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}
