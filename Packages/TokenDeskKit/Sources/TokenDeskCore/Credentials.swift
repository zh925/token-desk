import Foundation

/// Secret credential material that is intentionally neither codable nor printable.
public struct Credential: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    private let storage: Data

    /// Creates credential material, rejecting an empty value.
    public init(data: Data) throws {
        guard !data.isEmpty else {
            throw CredentialStoreError.emptyCredential
        }
        self.storage = data
    }

    /// Creates UTF-8 credential material without normalizing or trimming the value.
    public init(utf8Value: String) throws {
        try self.init(data: Data(utf8Value.utf8))
    }

    /// Provides scoped access to credential bytes for an authorized transport boundary.
    public func withData<Result>(_ body: (Data) throws -> Result) rethrows -> Result {
        try body(storage)
    }

    /// Credential material is always redacted when interpolated.
    public var description: String { "<redacted credential>" }

    /// Credential material is always redacted in debug output.
    public var debugDescription: String { description }

    /// Reflection does not expose the private byte storage.
    public var customMirror: Mirror {
        Mirror(self, children: ["value": description])
    }
}

/// The only credential state presentation code may consume.
public enum CredentialConfigurationStatus: Equatable, Sendable {
    case notConfigured
    case configured
}

/// Stable, non-secret failures exposed by a credential persistence boundary.
public enum CredentialStoreError: Error, Equatable, Sendable {
    case emptyCredential
    case notFound
    case accessDenied
    case interactionNotAllowed
    case cancelled
    case invalidStoredValue
    case unexpectedStatus(Int32)
}

/// Persists secret material separately from account configuration and database records.
public protocol CredentialStore: Sendable {
    /// Adds a credential or atomically replaces the existing value for an account.
    func save(_ credential: Credential, for accountID: AccountID) throws -> CredentialReference

    /// Reads credential material only at an authorized connector boundary.
    func credential(for reference: CredentialReference) throws -> Credential

    /// Replaces an existing credential, failing when no item exists.
    func replace(_ credential: Credential, for reference: CredentialReference) throws

    /// Removes a credential. Removing an already absent item is successful.
    func delete(for reference: CredentialReference) throws

    /// Returns presence only, so presentation state never receives credential material.
    func configurationStatus(for reference: CredentialReference) throws
        -> CredentialConfigurationStatus
}
