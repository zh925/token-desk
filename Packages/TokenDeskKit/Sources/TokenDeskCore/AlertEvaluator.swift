import Foundation

/// Validation failures for configurable local alert rules.
public enum AlertRuleError: Error, Equatable, Sendable {
    case invalidIdentifier
    case invalidThreshold
    case invalidCooldown
    case invalidQuietHours
    case missingCurrency
    case unexpectedCurrency
}

/// The four independently evaluated P0 alert categories.
public enum AlertKind: String, Codable, CaseIterable, Sendable {
    case planPercent
    case budgetPercent
    case balanceFloor
    case syncFailure
}

/// A local time-of-day interval during which notifications are deferred.
public struct AlertQuietHours: Codable, Equatable, Hashable, Sendable {
    /// Inclusive minute after local midnight, from 0 through 1439.
    public let startMinute: Int
    /// Exclusive minute after local midnight, from 0 through 1439.
    public let endMinute: Int
    /// IANA time zone used to interpret both minute boundaries.
    public let timeZoneIdentifier: String

    /// Creates a non-empty quiet interval, including intervals that cross midnight.
    public init(startMinute: Int, endMinute: Int, timeZoneIdentifier: String) throws {
        guard (0..<24 * 60).contains(startMinute),
            (0..<24 * 60).contains(endMinute),
            startMinute != endMinute,
            TimeZone(identifier: timeZoneIdentifier) != nil
        else {
            throw AlertRuleError.invalidQuietHours
        }
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// Returns whether an instant falls inside the end-exclusive local quiet interval.
    public func contains(_ date: Date, calendar inputCalendar: Calendar = .current) -> Bool {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return false }
        var calendar = inputCalendar
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return false }
        let value = hour * 60 + minute
        if startMinute < endMinute {
            return value >= startMinute && value < endMinute
        }
        return value >= startMinute || value < endMinute
    }
}

/// A provider/account-scoped alert rule persisted independently from observations.
public struct AlertRule: Codable, Equatable, Hashable, Sendable {
    /// Stable persistence identifier.
    public let id: String
    /// Optional Provider scope; nil applies across Providers.
    public let providerID: ProviderID?
    /// Optional account scope; requires a Provider scope.
    public let accountID: AccountID?
    /// Alert category and comparison direction.
    public let kind: AlertKind
    /// Exact non-negative threshold.
    public let threshold: Decimal
    /// Required balance currency; absent for non-balance rules.
    public let currency: CurrencyCode?
    /// Whether evaluation may trigger a notification.
    public let isEnabled: Bool
    /// Minimum seconds between notifications for the rule.
    public let cooldownSeconds: TimeInterval
    /// Optional local interval during which notifications are deferred.
    public let quietHours: AlertQuietHours?

    /// Creates and validates one provider/account-scoped rule.
    public init(
        id: String,
        providerID: ProviderID? = nil,
        accountID: AccountID? = nil,
        kind: AlertKind,
        threshold: Decimal,
        currency: CurrencyCode? = nil,
        isEnabled: Bool = true,
        cooldownSeconds: TimeInterval,
        quietHours: AlertQuietHours? = nil
    ) throws {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { throw AlertRuleError.invalidIdentifier }
        guard threshold >= 0 else { throw AlertRuleError.invalidThreshold }
        guard cooldownSeconds >= 0, cooldownSeconds.isFinite else {
            throw AlertRuleError.invalidCooldown
        }
        guard accountID == nil || providerID != nil else { throw AlertRuleError.invalidIdentifier }
        if kind == .balanceFloor, currency == nil { throw AlertRuleError.missingCurrency }
        if kind != .balanceFloor, currency != nil { throw AlertRuleError.unexpectedCurrency }
        self.id = trimmedID
        self.providerID = providerID
        self.accountID = accountID
        self.kind = kind
        self.threshold = threshold
        self.currency = currency
        self.isEnabled = isEnabled
        self.cooldownSeconds = cooldownSeconds
        self.quietHours = quietHours
    }
}

/// One normalized, non-secret value consumed by an alert rule.
public struct AlertObservation: Equatable, Sendable {
    /// Provider that produced the observed value.
    public let providerID: ProviderID
    /// Account that produced the value, when the observation is account-scoped.
    public let accountID: AccountID?
    /// Alert category represented by the value.
    public let kind: AlertKind
    /// Exact non-negative percentage, balance amount, or failure duration in seconds.
    public let value: Decimal
    /// Required balance currency; absent for other observation kinds.
    public let currency: CurrencyCode?
    /// Instant at which the value was observed.
    public let observedAt: Date
    /// Traceable, non-secret provenance of the value.
    public let source: DataSource

    /// Creates and validates a normalized alert observation.
    public init(
        providerID: ProviderID,
        accountID: AccountID? = nil,
        kind: AlertKind,
        value: Decimal,
        currency: CurrencyCode? = nil,
        observedAt: Date,
        source: DataSource
    ) throws {
        guard value >= 0 else { throw AlertRuleError.invalidThreshold }
        if kind == .balanceFloor, currency == nil { throw AlertRuleError.missingCurrency }
        if kind != .balanceFloor, currency != nil { throw AlertRuleError.unexpectedCurrency }
        self.providerID = providerID
        self.accountID = accountID
        self.kind = kind
        self.value = value
        self.currency = currency
        self.observedAt = observedAt
        self.source = source
    }
}

/// Durable state needed to suppress duplicates without losing deferred quiet-hour alerts.
public struct AlertEvaluationState: Codable, Equatable, Sendable {
    /// Whether the most recently applicable observation breached the threshold.
    public let isBreached: Bool
    /// Whether the current uninterrupted breach has already notified the user.
    public let notifiedForCurrentBreach: Bool
    /// Most recent notification instant, retained across recovery for cooldown checks.
    public let lastNotifiedAt: Date?

    /// Creates durable evaluator state while normalizing impossible combinations.
    public init(
        isBreached: Bool = false,
        notifiedForCurrentBreach: Bool = false,
        lastNotifiedAt: Date? = nil
    ) {
        self.isBreached = isBreached
        self.notifiedForCurrentBreach = isBreached && notifiedForCurrentBreach
        self.lastNotifiedAt = lastNotifiedAt
    }
}

/// Why a breached rule did not schedule another notification.
public enum AlertSuppressionReason: String, Codable, Equatable, Sendable {
    case quietHours
    case cooldown
    case alreadyNotified
}

/// A privacy-safe notification and routing payload.
public struct AlertNotification: Equatable, Sendable {
    /// Non-sensitive notification title.
    public let title: String
    /// Non-sensitive notification body.
    public let body: String
    /// Provider route used when the notification is opened.
    public let providerID: ProviderID
    /// Optional account route used when the notification is opened.
    public let accountID: AccountID?

    /// Creates a privacy-safe notification payload.
    public init(title: String, body: String, providerID: ProviderID, accountID: AccountID?) {
        self.title = title
        self.body = body
        self.providerID = providerID
        self.accountID = accountID
    }

    /// A percent-encoded app route; provider and account identifiers stay out of the message body.
    public var deepLink: URL? {
        var components = URLComponents()
        components.scheme = "tokendesk"
        components.host = "provider"
        var items = [URLQueryItem(name: "provider", value: providerID.rawValue)]
        if let accountID {
            items.append(URLQueryItem(name: "account", value: accountID.rawValue))
        }
        components.queryItems = items
        return components.url
    }
}

/// The externally visible result of one deterministic alert evaluation.
public enum AlertEvaluationAction: Equatable, Sendable {
    case none
    case triggered(AlertNotification)
    case recovered
    case suppressed(AlertSuppressionReason)
}

/// Updated state paired with the action that persistence and notification layers should apply.
public struct AlertEvaluation: Equatable, Sendable {
    /// Persistence or notification action derived for this evaluation.
    public let action: AlertEvaluationAction
    /// State callers persist for the rule's next evaluation.
    public let state: AlertEvaluationState

    /// Creates an action and its corresponding next state.
    public init(action: AlertEvaluationAction, state: AlertEvaluationState) {
        self.action = action
        self.state = state
    }
}

/// Stateless rule evaluator; callers persist the returned state and schedule only `.triggered`.
public struct AlertEvaluator: Sendable {
    /// Creates a stateless alert evaluator.
    public init() {}

    /// Evaluates one rule and observation without performing persistence or notification side effects.
    public func evaluate(
        rule: AlertRule,
        observation: AlertObservation,
        previous: AlertEvaluationState = AlertEvaluationState(),
        at now: Date
    ) -> AlertEvaluation {
        guard rule.isEnabled, Self.applies(rule, to: observation) else {
            return AlertEvaluation(action: .none, state: previous)
        }
        let breached: Bool
        switch rule.kind {
        case .balanceFloor:
            breached = observation.value <= rule.threshold
        case .planPercent, .budgetPercent, .syncFailure:
            breached = observation.value >= rule.threshold
        }

        guard breached else {
            if previous.isBreached {
                return AlertEvaluation(
                    action: .recovered,
                    state: AlertEvaluationState(lastNotifiedAt: previous.lastNotifiedAt)
                )
            }
            return AlertEvaluation(action: .none, state: previous)
        }

        if previous.isBreached, previous.notifiedForCurrentBreach {
            return AlertEvaluation(
                action: .suppressed(.alreadyNotified),
                state: previous
            )
        }

        let breachedState = AlertEvaluationState(
            isBreached: true,
            notifiedForCurrentBreach: false,
            lastNotifiedAt: previous.lastNotifiedAt
        )
        if rule.quietHours?.contains(now) == true {
            return AlertEvaluation(action: .suppressed(.quietHours), state: breachedState)
        }
        if let lastNotifiedAt = previous.lastNotifiedAt,
            now.timeIntervalSince(lastNotifiedAt) < rule.cooldownSeconds
        {
            return AlertEvaluation(action: .suppressed(.cooldown), state: breachedState)
        }

        return AlertEvaluation(
            action: .triggered(Self.notification(for: observation)),
            state: AlertEvaluationState(
                isBreached: true,
                notifiedForCurrentBreach: true,
                lastNotifiedAt: now
            )
        )
    }

    private static func applies(_ rule: AlertRule, to observation: AlertObservation) -> Bool {
        guard rule.kind == observation.kind else { return false }
        if let providerID = rule.providerID, providerID != observation.providerID { return false }
        if let accountID = rule.accountID, accountID != observation.accountID { return false }
        return rule.currency == nil || rule.currency == observation.currency
    }

    private static func notification(for observation: AlertObservation) -> AlertNotification {
        let content: (String, String)
        switch observation.kind {
        case .planPercent:
            content = ("Token Desk 套餐提醒", "套餐用量已达到设置的阈值。")
        case .budgetPercent:
            content = ("Token Desk 预算提醒", "本月费用已达到设置的预算阈值。")
        case .balanceFloor:
            content = ("Token Desk 余额提醒", "可用余额已低于设置的下限。")
        case .syncFailure:
            content = ("Token Desk 同步提醒", "数据同步失败时间已达到设置的阈值。")
        }
        return AlertNotification(
            title: content.0,
            body: content.1,
            providerID: observation.providerID,
            accountID: observation.accountID
        )
    }
}
