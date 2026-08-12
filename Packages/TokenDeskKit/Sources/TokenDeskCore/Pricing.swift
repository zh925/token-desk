import Foundation

/// Failures raised by versioned price lookup and exact decimal cost calculation.
public enum PricingError: Error, Equatable, Sendable {
    case invalidRuleIdentifier
    case invalidVersion
    case invalidEffectiveInterval
    case negativeRate
    case noMatchingRule
    case usageOutsideEffectiveInterval
    case providerMismatch
    case modelMismatch
}

/// Per-million token prices for every independently metered token category.
public struct TokenRates: Codable, Equatable, Hashable, Sendable {
    /// Non-cached input price per million tokens.
    public let input: Decimal
    /// Generated output price per million tokens.
    public let output: Decimal
    /// Cache-read input price per million tokens.
    public let cacheRead: Decimal
    /// Cache-write input price per million tokens.
    public let cacheWrite: Decimal

    /// Creates non-negative category rates without presentation rounding.
    public init(
        input: Decimal,
        output: Decimal,
        cacheRead: Decimal,
        cacheWrite: Decimal
    ) throws {
        guard input >= 0, output >= 0, cacheRead >= 0, cacheWrite >= 0 else {
            throw PricingError.negativeRate
        }
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }
}

/// One immutable catalog version over an end-exclusive effective interval.
public struct PricingRule: Codable, Equatable, Hashable, Sendable {
    /// Stable identifier for this catalog rule.
    public let id: String
    /// Provider type whose usage the rule prices.
    public let providerType: ProviderType
    /// An exact model name or `*` as a Provider-wide fallback.
    public let modelMatch: String
    /// ISO 4217 currency used by all category rates.
    public let currency: CurrencyCode
    /// An exact region or `global` as a fallback.
    public let region: String
    /// Monotonically increasing version within a matching rule series.
    public let version: Int
    /// Inclusive start of the rule's validity.
    public let effectiveFrom: Date
    /// Optional exclusive end of the rule's validity.
    public let effectiveTo: Date?
    /// Per-million rates for every metered category.
    public let rates: TokenRates
    /// Traceable non-secret origin of the published price.
    public let source: DataSource
    /// Last catalog update instant.
    public let updatedAt: Date

    /// Creates and validates one versioned effective-dated rule.
    public init(
        id: String,
        providerType: ProviderType,
        modelMatch: String,
        currency: CurrencyCode,
        region: String,
        version: Int,
        effectiveFrom: Date,
        effectiveTo: Date? = nil,
        rates: TokenRates,
        source: DataSource,
        updatedAt: Date
    ) throws {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelMatch.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { throw PricingError.invalidRuleIdentifier }
        guard !trimmedModel.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "pricingModelMatch")
        }
        guard !trimmedRegion.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "pricingRegion")
        }
        guard version > 0 else { throw PricingError.invalidVersion }
        if let effectiveTo, effectiveFrom >= effectiveTo {
            throw PricingError.invalidEffectiveInterval
        }
        self.id = trimmedID
        self.providerType = providerType
        self.modelMatch = trimmedModel
        self.currency = currency
        self.region = trimmedRegion
        self.version = version
        self.effectiveFrom = effectiveFrom
        self.effectiveTo = effectiveTo
        self.rates = rates
        self.source = source
        self.updatedAt = updatedAt
    }

    /// Returns whether the instant falls in the end-exclusive effective interval.
    public func isEffective(at date: Date) -> Bool {
        guard effectiveFrom <= date else { return false }
        return effectiveTo.map { date < $0 } ?? true
    }

    /// Applies exact-match precedence while permitting explicit wildcard fallbacks.
    public func matches(model: String, region requestedRegion: String) -> Bool {
        (modelMatch == model || modelMatch == "*")
            && (region == requestedRegion || region == "global")
    }
}

/// Persistent price lookup; implementations may cache rules in SQLite.
public protocol PricingCatalog: Sendable {
    func upsert(_ rules: [PricingRule]) throws
    func rule(
        providerType: ProviderType,
        model: String,
        currency: CurrencyCode,
        region: String,
        effectiveAt: Date
    ) throws -> PricingRule?
}

/// Exact, unrounded token-cost calculation with explicit estimate provenance.
public struct CostCalculator: Sendable {
    /// Creates a stateless exact-decimal calculator.
    public init() {}

    /// Official Provider costs always win; an estimate is produced only when none exist.
    public func resolve(
        officialCosts: [CostSnapshot],
        usage: TokenUsageBucket,
        providerType: ProviderType,
        currency: CurrencyCode,
        region: String,
        catalog: any PricingCatalog,
        calculatedAt: Date
    ) throws -> [CostSnapshot] {
        guard officialCosts.isEmpty else { return officialCosts }

        guard
            let rule = try catalog.rule(
                providerType: providerType,
                model: usage.model,
                currency: currency,
                region: region,
                effectiveAt: usage.period.interval.start
            )
        else {
            throw PricingError.noMatchingRule
        }
        return [
            try estimate(usage: usage, providerType: providerType, rule: rule, at: calculatedAt)
        ]
    }

    /// Calculates an estimated cost from all four token categories and one validated rule.
    public func estimate(
        usage: TokenUsageBucket,
        providerType: ProviderType,
        rule: PricingRule,
        at calculatedAt: Date
    ) throws -> CostSnapshot {
        guard rule.providerType == providerType else { throw PricingError.providerMismatch }
        guard rule.modelMatch == usage.model || rule.modelMatch == "*" else {
            throw PricingError.modelMismatch
        }
        guard rule.isEffective(at: usage.period.interval.start) else {
            throw PricingError.usageOutsideEffectiveInterval
        }

        let million = Decimal(1_000_000)
        let amount =
            Decimal(usage.tokens.input.rawValue) * rule.rates.input / million
            + Decimal(usage.tokens.output.rawValue) * rule.rates.output / million
            + Decimal(usage.tokens.cachedInput.rawValue) * rule.rates.cacheRead / million
            + Decimal(usage.tokens.cacheWrite.rawValue) * rule.rates.cacheWrite / million
        let source = try DataSource(
            kind: .estimated,
            identifier: "pricing_catalog:\(rule.id):v\(rule.version)"
        )
        return CostSnapshot(
            providerID: usage.providerID,
            accountID: usage.accountID,
            projectReference: usage.projectReference,
            workspaceReference: usage.workspaceReference,
            period: usage.period,
            money: Money(amount: amount, currency: rule.currency),
            metadata: ObservationMetadata(source: source, updatedAt: calculatedAt, isStale: false)
        )
    }
}
