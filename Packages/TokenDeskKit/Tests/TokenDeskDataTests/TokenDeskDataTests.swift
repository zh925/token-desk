import Foundation
import Security
import Testing
import TokenDeskCore
@testable import TokenDeskData

@Test
func dataModuleLinksGRDB() {
    #expect(TokenDeskDataModule.databaseEngine == "GRDB")
    #expect(TokenDeskDataModule.isDatabaseLibraryLinked)
}

@Test
func keychainStoreAddsReadsReportsAndDeletesCredential() throws {
    let client = InMemoryKeychainClient()
    let store = KeychainCredentialStore(service: "test.credentials", client: client)
    let accountID = try AccountID(rawValue: "account-1")
    let secret = try Credential(utf8Value: "fixture-redacted-first")

    let reference = try store.save(secret, for: accountID)

    #expect(reference.rawValue == accountID.rawValue)
    #expect(try store.configurationStatus(for: reference) == .configured)
    #expect(try utf8Value(of: store.credential(for: reference)) == "fixture-redacted-first")

    try store.delete(for: reference)
    try store.delete(for: reference)
    #expect(try store.configurationStatus(for: reference) == .notConfigured)
    #expect(throws: CredentialStoreError.notFound) {
        try store.credential(for: reference)
    }
}

@Test
func savingExistingAccountReplacesCredentialWithoutChangingReference() throws {
    let client = InMemoryKeychainClient()
    let store = KeychainCredentialStore(service: "test.credentials", client: client)
    let accountID = try AccountID(rawValue: "account-2")
    let firstReference = try store.save(
        Credential(utf8Value: "fixture-redacted-first"),
        for: accountID
    )
    let secondReference = try store.save(
        Credential(utf8Value: "fixture-redacted-second"),
        for: accountID
    )

    #expect(firstReference == secondReference)
    #expect(
        try utf8Value(of: store.credential(for: secondReference))
            == "fixture-redacted-second"
    )
    #expect(client.addCount == 2)
    #expect(client.updateCount == 1)
}

@Test
func explicitReplacementRequiresAnExistingCredential() throws {
    let store = KeychainCredentialStore(
        service: "test.credentials",
        client: InMemoryKeychainClient()
    )
    let reference = try CredentialReference(rawValue: "missing-account")

    #expect(throws: CredentialStoreError.notFound) {
        try store.replace(
            Credential(utf8Value: "fixture-redacted-replacement"),
            for: reference
        )
    }
}

@Test
func keychainFailuresMapToStableCredentialErrors() throws {
    let reference = try CredentialReference(rawValue: "account-3")
    let credential = try Credential(utf8Value: "fixture-redacted-value")

    let deniedClient = InMemoryKeychainClient(forcedStatus: errSecAuthFailed)
    let deniedStore = KeychainCredentialStore(service: "test.credentials", client: deniedClient)
    #expect(throws: CredentialStoreError.accessDenied) {
        try deniedStore.save(credential, for: AccountID(rawValue: reference.rawValue))
    }
    #expect(throws: CredentialStoreError.accessDenied) {
        try deniedStore.configurationStatus(for: reference)
    }
    #expect(throws: CredentialStoreError.accessDenied) {
        try deniedStore.delete(for: reference)
    }

    let lockedClient = InMemoryKeychainClient(forcedStatus: errSecInteractionNotAllowed)
    let lockedStore = KeychainCredentialStore(service: "test.credentials", client: lockedClient)
    #expect(throws: CredentialStoreError.interactionNotAllowed) {
        try lockedStore.credential(for: reference)
    }

    let cancelledClient = InMemoryKeychainClient(forcedStatus: errSecUserCanceled)
    let cancelledStore = KeychainCredentialStore(
        service: "test.credentials",
        client: cancelledClient
    )
    #expect(throws: CredentialStoreError.cancelled) {
        try cancelledStore.replace(credential, for: reference)
    }
}

@Test
func productionKeychainQueryIsDeviceLocalAndAvailableAfterUnlock() throws {
    let query = SecurityKeychainClient.addQuery(
        service: "test.credentials",
        account: "account-4",
        data: Data("fixture-redacted-value".utf8)
    )

    let itemClass = try #require(query[kSecClass])
    let accessibility = try #require(query[kSecAttrAccessible])
    let synchronizable = try #require(query[kSecAttrSynchronizable])
    let usesDataProtection = try #require(query[kSecUseDataProtectionKeychain])

    #expect(CFEqual(itemClass as CFTypeRef, kSecClassGenericPassword))
    #expect(
        CFEqual(
            accessibility as CFTypeRef,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
    )
    #expect(CFEqual(synchronizable as CFTypeRef, kCFBooleanFalse))
    #expect(CFEqual(usesDataProtection as CFTypeRef, kCFBooleanTrue))
}

private func utf8Value(of credential: Credential) throws -> String {
    try credential.withData { data in
        guard let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.invalidStoredValue
        }
        return value
    }
}

private final class InMemoryKeychainClient: KeychainClient, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private let forcedStatus: OSStatus?
    private(set) var addCount = 0
    private(set) var updateCount = 0

    init(forcedStatus: OSStatus? = nil) {
        self.forcedStatus = forcedStatus
    }

    func add(service: String, account: String, data: Data) -> OSStatus {
        lock.withLock {
            addCount += 1
            if let forcedStatus { return forcedStatus }
            let key = key(service: service, account: account)
            guard values[key] == nil else { return errSecDuplicateItem }
            values[key] = data
            return errSecSuccess
        }
    }

    func update(service: String, account: String, data: Data) -> OSStatus {
        lock.withLock {
            updateCount += 1
            if let forcedStatus { return forcedStatus }
            let key = key(service: service, account: account)
            guard values[key] != nil else { return errSecItemNotFound }
            values[key] = data
            return errSecSuccess
        }
    }

    func read(service: String, account: String) -> KeychainReadResult {
        lock.withLock {
            if let forcedStatus { return KeychainReadResult(status: forcedStatus, data: nil) }
            guard let data = values[key(service: service, account: account)] else {
                return KeychainReadResult(status: errSecItemNotFound, data: nil)
            }
            return KeychainReadResult(status: errSecSuccess, data: data)
        }
    }

    func contains(service: String, account: String) -> OSStatus {
        lock.withLock {
            if let forcedStatus { return forcedStatus }
            return values[key(service: service, account: account)] == nil
                ? errSecItemNotFound : errSecSuccess
        }
    }

    func delete(service: String, account: String) -> OSStatus {
        lock.withLock {
            if let forcedStatus { return forcedStatus }
            return values.removeValue(forKey: key(service: service, account: account)) == nil
                ? errSecItemNotFound : errSecSuccess
        }
    }

    private func key(service: String, account: String) -> String {
        service + "\u{1F}" + account
    }
}
