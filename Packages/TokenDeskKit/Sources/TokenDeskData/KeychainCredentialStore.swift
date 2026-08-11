import Foundation
import Security
import TokenDeskCore

struct KeychainReadResult: Sendable {
    let status: OSStatus
    let data: Data?
}

protocol KeychainClient: Sendable {
    func add(service: String, account: String, data: Data) -> OSStatus
    func update(service: String, account: String, data: Data) -> OSStatus
    func read(service: String, account: String) -> KeychainReadResult
    func contains(service: String, account: String) -> OSStatus
    func delete(service: String, account: String) -> OSStatus
}

struct SecurityKeychainClient: KeychainClient {
    static func baseQuery(service: String, account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain: kCFBooleanTrue as Any,
        ]
    }

    static func addQuery(service: String, account: String, data: Data) -> [CFString: Any] {
        var query = baseQuery(service: service, account: account)
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData] = data
        return query
    }

    func add(service: String, account: String, data: Data) -> OSStatus {
        SecItemAdd(
            Self.addQuery(service: service, account: account, data: data) as CFDictionary,
            nil
        )
    }

    func update(service: String, account: String, data: Data) -> OSStatus {
        SecItemUpdate(
            Self.baseQuery(service: service, account: account) as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
    }

    func read(service: String, account: String) -> KeychainReadResult {
        var query = Self.baseQuery(service: service, account: account)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = kCFBooleanTrue

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return KeychainReadResult(status: status, data: result as? Data)
    }

    func contains(service: String, account: String) -> OSStatus {
        var query = Self.baseQuery(service: service, account: account)
        query[kSecMatchLimit] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil)
    }

    func delete(service: String, account: String) -> OSStatus {
        SecItemDelete(Self.baseQuery(service: service, account: account) as CFDictionary)
    }
}

/// Stores Provider credentials in the local data-protection Keychain.
public final class KeychainCredentialStore: CredentialStore {
    /// The app-scoped Keychain service used for all Provider account items.
    public static let defaultService = "app.tokendesk.TokenDesk.credentials"

    private let service: String
    private let client: any KeychainClient

    /// Creates the production store using Keychain Services.
    public convenience init(service: String = defaultService) {
        self.init(service: service, client: SecurityKeychainClient())
    }

    init(service: String, client: any KeychainClient) {
        self.service = service
        self.client = client
    }

    /// Adds or replaces the device-local credential for an account.
    public func save(_ credential: Credential, for accountID: AccountID) throws
        -> CredentialReference
    {
        let reference = try CredentialReference(rawValue: accountID.rawValue)
        let addStatus = credential.withData {
            client.add(service: service, account: reference.rawValue, data: $0)
        }

        if addStatus == errSecDuplicateItem {
            try replace(credential, for: reference)
        } else {
            try Self.validate(addStatus)
        }
        return reference
    }

    /// Reads an existing credential by its opaque account reference.
    public func credential(for reference: CredentialReference) throws -> Credential {
        let result = client.read(service: service, account: reference.rawValue)
        try Self.validate(result.status)
        guard let data = result.data, !data.isEmpty else {
            throw CredentialStoreError.invalidStoredValue
        }
        return try Credential(data: data)
    }

    /// Replaces an existing credential without changing its account reference.
    public func replace(_ credential: Credential, for reference: CredentialReference) throws {
        let status = credential.withData {
            client.update(service: service, account: reference.rawValue, data: $0)
        }
        try Self.validate(status)
    }

    /// Removes an existing credential, treating an already absent item as success.
    public func delete(for reference: CredentialReference) throws {
        let status = client.delete(service: service, account: reference.rawValue)
        guard status != errSecItemNotFound else { return }
        try Self.validate(status)
    }

    /// Reports only whether a credential is configured.
    public func configurationStatus(for reference: CredentialReference) throws
        -> CredentialConfigurationStatus
    {
        let status = client.contains(service: service, account: reference.rawValue)
        if status == errSecItemNotFound {
            return .notConfigured
        }
        try Self.validate(status)
        return .configured
    }

    private static func validate(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            throw CredentialStoreError.notFound
        case errSecAuthFailed, errSecMissingEntitlement:
            throw CredentialStoreError.accessDenied
        case errSecInteractionNotAllowed:
            throw CredentialStoreError.interactionNotAllowed
        case errSecUserCanceled:
            throw CredentialStoreError.cancelled
        default:
            throw CredentialStoreError.unexpectedStatus(status)
        }
    }
}
