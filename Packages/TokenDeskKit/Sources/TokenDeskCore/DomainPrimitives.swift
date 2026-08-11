import Foundation

/// Validation and arithmetic failures produced by Token Desk domain value types.
public enum DomainModelError: Error, Equatable, Sendable {
    case emptyIdentifier(field: String)
    case invalidCurrencyCode(String)
    case negativeTokenCount(Int64)
    case tokenCountOverflow
    case currencyMismatch(expected: CurrencyCode, actual: CurrencyCode)
    case decimalArithmeticFailure
    case invalidInterval
    case invalidTimeZone(String)
    case invalidConfidence(Decimal)
}

/// A stable local identifier for a configured Provider instance.
public struct ProviderID: Codable, Hashable, Sendable {
    /// The non-empty, trimmed local identifier.
    public let rawValue: String

    /// Creates an identifier, rejecting empty or whitespace-only input.
    public init(rawValue: String) throws {
        self.rawValue = try Self.validated(rawValue, field: "providerId")
    }

    /// Decodes and validates a single string value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    /// Encodes the identifier as a single string value.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func validated(_ value: String, field: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: field)
        }
        return trimmed
    }
}

/// A stable local identifier for an account. It is safe to log in place of remote account IDs.
public struct AccountID: Codable, Hashable, Sendable {
    /// The non-empty, trimmed local identifier.
    public let rawValue: String

    /// Creates an identifier, rejecting empty or whitespace-only input.
    public init(rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "accountId")
        }
        self.rawValue = trimmed
    }

    /// Decodes and validates a single string value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    /// Encodes the identifier as a single string value.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// An opaque reference to a Keychain item. This type never contains credential material.
public struct CredentialReference: Codable, Hashable, Sendable {
    /// The opaque Keychain lookup key.
    public let rawValue: String

    /// Creates a reference, rejecting empty or whitespace-only input.
    public init(rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "credentialReference")
        }
        self.rawValue = trimmed
    }

    /// Decodes and validates a single string value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    /// Encodes the reference as a single string value.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// An ISO 4217 currency code, normalized to uppercase ASCII.
public struct CurrencyCode: Codable, Hashable, Sendable {
    /// The normalized three-letter uppercase code.
    public let rawValue: String

    /// Creates a normalized code, rejecting values that are not three ASCII letters.
    public init(rawValue: String) throws {
        let normalized = rawValue.uppercased()
        let isASCIILetters = normalized.utf8.allSatisfy { byte in byte >= 65 && byte <= 90 }
        guard normalized.utf8.count == 3, isASCIILetters else {
            throw DomainModelError.invalidCurrencyCode(rawValue)
        }
        self.rawValue = normalized
    }

    /// Decodes, normalizes, and validates a single string value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    /// Encodes the normalized code as a single string value.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A decimal monetary amount paired with its currency. Values are never rounded in the domain layer.
public struct Money: Codable, Equatable, Hashable, Sendable {
    /// The unrounded decimal amount, which may be negative for adjustments.
    public let amount: Decimal
    /// The currency in which the amount is denominated.
    public let currency: CurrencyCode

    /// Creates a monetary amount without applying presentation rounding.
    public init(amount: Decimal, currency: CurrencyCode) {
        self.amount = amount
        self.currency = currency
    }

    /// Adds another amount only when both values use the same currency.
    public func adding(_ other: Money) throws -> Money {
        guard currency == other.currency else {
            throw DomainModelError.currencyMismatch(expected: currency, actual: other.currency)
        }

        var lhs = amount
        var rhs = other.amount
        var result = Decimal()
        let calculation = NSDecimalAdd(&result, &lhs, &rhs, .plain)
        guard calculation == .noError else {
            throw DomainModelError.decimalArithmeticFailure
        }
        return Money(amount: result, currency: currency)
    }
}

/// A non-negative token quantity stored with exact `Int64` precision.
public struct TokenCount: Codable, Equatable, Hashable, Sendable {
    /// The exact non-negative token quantity.
    public let rawValue: Int64

    /// Creates a token count, rejecting negative quantities.
    public init(rawValue: Int64) throws {
        guard rawValue >= 0 else {
            throw DomainModelError.negativeTokenCount(rawValue)
        }
        self.rawValue = rawValue
    }

    /// Decodes and validates a single integer value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(Int64.self))
    }

    /// Encodes the count as a single integer value.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Adds token counts and reports `Int64` overflow as a domain error.
    public func adding(_ other: TokenCount) throws -> TokenCount {
        let (sum, overflow) = rawValue.addingReportingOverflow(other.rawValue)
        guard !overflow else {
            throw DomainModelError.tokenCountOverflow
        }
        return try TokenCount(rawValue: sum)
    }

    /// The additive identity for token quantities.
    public static let zero = TokenCount(uncheckedRawValue: 0)

    private init(uncheckedRawValue: Int64) {
        rawValue = uncheckedRawValue
    }
}

/// A raw usage percentage. Out-of-range provider values remain observable for diagnostics.
public struct UsagePercent: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    /// The source value, including values outside the normal 0...100 range.
    public let rawValue: Decimal

    /// Creates a percentage while preserving anomalous source values.
    public init(rawValue: Decimal) {
        self.rawValue = rawValue
    }

    /// Decodes the raw percentage as a single decimal value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(Decimal.self))
    }

    /// Encodes the raw percentage as a single decimal value.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// A presentation-safe value in the closed range 0...100.
    public var displayValue: Decimal {
        min(max(rawValue, 0), 100)
    }

    /// Whether the source supplied a value outside the expected 0...100 range.
    public var isOutOfBounds: Bool {
        rawValue < 0 || rawValue > 100
    }
}

/// Confidence in an inferred source value, constrained to the closed range 0...1.
public struct SourceConfidence: Codable, Equatable, Hashable, Sendable {
    /// The confidence ratio in the closed range 0...1.
    public let rawValue: Decimal

    /// Creates a confidence ratio and rejects values outside 0...1.
    public init(rawValue: Decimal) throws {
        guard rawValue >= 0, rawValue <= 1 else {
            throw DomainModelError.invalidConfidence(rawValue)
        }
        self.rawValue = rawValue
    }

    /// Decodes and validates a single decimal ratio.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(Decimal.self))
    }

    /// Encodes the confidence as a single decimal value.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
