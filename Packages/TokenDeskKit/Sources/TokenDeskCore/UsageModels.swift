import Foundation

/// Supported calendar bucket boundaries for token and cost aggregation.
public enum UsageGranularity: String, Codable, CaseIterable, Sendable {
    case minute
    case hour
    case day
    case week
    case month
}

/// An end-exclusive usage interval together with the time zone that defined its boundary.
public struct UsagePeriod: Codable, Equatable, Hashable, Sendable {
    /// The end-exclusive UTC interval.
    public let interval: DateInterval
    /// The time zone that defined the calendar boundary.
    public let timeZoneIdentifier: String

    /// Creates a positive interval with an explicit valid time zone.
    public init(interval: DateInterval, timeZoneIdentifier: String) throws {
        guard interval.duration > 0 else {
            throw DomainModelError.invalidInterval
        }
        guard TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw DomainModelError.invalidTimeZone(timeZoneIdentifier)
        }
        self.interval = interval
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// Creates the calendar period containing a date using an explicit calendar and time zone.
    public static func containing(
        _ date: Date,
        granularity: UsageGranularity,
        calendar inputCalendar: Calendar,
        timeZone: TimeZone
    ) throws -> UsagePeriod {
        var calendar = inputCalendar
        calendar.timeZone = timeZone

        let component: Calendar.Component
        switch granularity {
        case .minute:
            component = .minute
        case .hour:
            component = .hour
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        }

        guard let interval = calendar.dateInterval(of: component, for: date) else {
            throw DomainModelError.invalidInterval
        }
        return try UsagePeriod(interval: interval, timeZoneIdentifier: timeZone.identifier)
    }
}

/// Input, output, and cache token quantities for one metered usage bucket.
public struct TokenBreakdown: Codable, Equatable, Hashable, Sendable {
    /// Non-cached input tokens.
    public let input: TokenCount
    /// Generated output tokens.
    public let output: TokenCount
    /// Cached input tokens read by the Provider.
    public let cachedInput: TokenCount
    /// Input tokens written to a Provider cache.
    public let cacheWrite: TokenCount

    /// Creates a token breakdown; omitted cache categories default to zero.
    public init(
        input: TokenCount,
        output: TokenCount,
        cachedInput: TokenCount = .zero,
        cacheWrite: TokenCount = .zero
    ) {
        self.input = input
        self.output = output
        self.cachedInput = cachedInput
        self.cacheWrite = cacheWrite
    }

    /// Returns a checked total across all token categories.
    public var total: TokenCount {
        get throws {
            try input.adding(output).adding(cachedInput).adding(cacheWrite)
        }
    }
}

/// The Token aggregate root. It deliberately contains no plan percentage, balance, or monetary value.
public struct TokenUsageBucket: Codable, Equatable, Hashable, Sendable {
    /// The configured Provider instance identifier.
    public let providerID: ProviderID
    /// The local account identifier.
    public let accountID: AccountID
    /// The optional opaque project boundary.
    public let projectReference: String?
    /// The Provider model name.
    public let model: String
    /// The calendar bucket size.
    public let granularity: UsageGranularity
    /// The end-exclusive calendar period.
    public let period: UsagePeriod
    /// The exact metered token quantities.
    public let tokens: TokenBreakdown
    /// The source and freshness of the bucket.
    public let metadata: ObservationMetadata

    /// Creates a token bucket, rejecting an empty model name.
    public init(
        providerID: ProviderID,
        accountID: AccountID,
        projectReference: String? = nil,
        model: String,
        granularity: UsageGranularity,
        period: UsagePeriod,
        tokens: TokenBreakdown,
        metadata: ObservationMetadata
    ) throws {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "model")
        }
        self.providerID = providerID
        self.accountID = accountID
        self.projectReference = projectReference
        self.model = trimmedModel
        self.granularity = granularity
        self.period = period
        self.tokens = tokens
        self.metadata = metadata
    }
}

/// The plan-window aggregate root. It has no Token or monetary conversion API.
public struct PlanWindow: Codable, Equatable, Hashable, Sendable {
    /// The configured Provider instance identifier.
    public let providerID: ProviderID
    /// The local account identifier.
    public let accountID: AccountID
    /// The Provider's plan name.
    public let planName: String
    /// The Provider's stable limit or window name.
    public let limitIdentifier: String
    /// The raw consumed percentage, including observable anomalies.
    public let usedPercent: UsagePercent
    /// The rolling or fixed window length in whole minutes.
    public let windowDurationMinutes: Int64
    /// The UTC instant at which this window resets.
    public let resetsAt: Date
    /// The account time zone used to present the reset boundary.
    public let timeZoneIdentifier: String
    /// Confidence in an inferred plan value, when applicable.
    public let confidence: SourceConfidence?
    /// The source and freshness of the window.
    public let metadata: ObservationMetadata

    /// Creates a positive-duration plan window with an explicit valid time zone.
    public init(
        providerID: ProviderID,
        accountID: AccountID,
        planName: String,
        limitIdentifier: String,
        usedPercent: UsagePercent,
        windowDurationMinutes: Int64,
        resetsAt: Date,
        timeZoneIdentifier: String,
        confidence: SourceConfidence? = nil,
        metadata: ObservationMetadata
    ) throws {
        let trimmedPlanName = planName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLimit = limitIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPlanName.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "planName")
        }
        guard !trimmedLimit.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "limitIdentifier")
        }
        guard windowDurationMinutes > 0 else {
            throw DomainModelError.invalidInterval
        }
        guard TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw DomainModelError.invalidTimeZone(timeZoneIdentifier)
        }
        self.providerID = providerID
        self.accountID = accountID
        self.planName = trimmedPlanName
        self.limitIdentifier = trimmedLimit
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.confidence = confidence
        self.metadata = metadata
    }
}

/// A monetary charge or adjustment. Costs remain independent from Token and plan aggregates.
public struct CostSnapshot: Codable, Equatable, Hashable, Sendable {
    /// The configured Provider instance identifier.
    public let providerID: ProviderID
    /// The local account identifier.
    public let accountID: AccountID
    /// The optional opaque project boundary.
    public let projectReference: String?
    /// The period to which the charge or adjustment applies.
    public let period: UsagePeriod
    /// The unrounded amount and its currency.
    public let money: Money
    /// The source and freshness of the cost.
    public let metadata: ObservationMetadata

    /// Creates a cost snapshot. Negative amounts remain valid for adjustments.
    public init(
        providerID: ProviderID,
        accountID: AccountID,
        projectReference: String? = nil,
        period: UsagePeriod,
        money: Money,
        metadata: ObservationMetadata
    ) {
        self.providerID = providerID
        self.accountID = accountID
        self.projectReference = projectReference
        self.period = period
        self.money = money
        self.metadata = metadata
    }

    /// Whether this cost was estimated instead of returned by an official cost source.
    public var isEstimated: Bool {
        metadata.source.isEstimated
    }
}

/// A known balance at a point in time. Unknown balances are represented by the absence of a snapshot.
public struct BalanceSnapshot: Codable, Equatable, Hashable, Sendable {
    /// The configured Provider instance identifier.
    public let providerID: ProviderID
    /// The local account identifier.
    public let accountID: AccountID
    /// The known available amount and its currency.
    public let available: Money
    /// The source and freshness of the balance.
    public let metadata: ObservationMetadata

    /// Creates a known balance snapshot. Unknown balances have no snapshot.
    public init(
        providerID: ProviderID,
        accountID: AccountID,
        available: Money,
        metadata: ObservationMetadata
    ) {
        self.providerID = providerID
        self.accountID = accountID
        self.available = available
        self.metadata = metadata
    }
}
