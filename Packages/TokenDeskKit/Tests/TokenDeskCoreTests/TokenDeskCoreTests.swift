import Foundation
import Testing
import TokenDeskCore

@Test
func coreModuleNameIsStable() {
    #expect(TokenDeskCoreModule.name == "TokenDeskCore")
}

@Test
func publicDomainModelsAreSendable() {
    func requireSendable<T: Sendable>(_: T.Type) {}

    requireSendable(AccountReference.self)
    requireSendable(ProviderDescriptor.self)
    requireSendable(PlanWindow.self)
    requireSendable(TokenUsageBucket.self)
    requireSendable(CostSnapshot.self)
    requireSendable(BalanceSnapshot.self)
    requireSendable(Credential.self)
    requireSendable(CredentialConfigurationStatus.self)
}

@Test
func credentialMaterialIsNotSerializableAndRedactsDescriptions() throws {
    let credential = try Credential(utf8Value: "fixture-redacted-credential")

    #expect(String(describing: credential) == "<redacted credential>")
    #expect(String(reflecting: credential) == "<redacted credential>")
    #expect(credential.customMirror.children.first?.value as? String == "<redacted credential>")
    #expect(!(Credential.self is any Encodable.Type))
}

@Test
func accountConfigurationSerializesOnlyTheOpaqueCredentialReference() throws {
    let account = try AccountReference(
        id: AccountID(rawValue: "local-account"),
        providerID: ProviderID(rawValue: "openai-primary"),
        displayName: "Primary",
        scope: .personal,
        credentialReference: CredentialReference(rawValue: "local-account")
    )

    let json = try #require(String(data: JSONEncoder().encode(account), encoding: .utf8))

    #expect(json.contains("local-account"))
    #expect(!json.contains("fixture-redacted-credential"))
}

@Test
func emptyCredentialMaterialIsRejected() {
    #expect(throws: CredentialStoreError.emptyCredential) {
        try Credential(data: Data())
    }
}

@Test
func moneyPreservesDecimalPrecisionAndRejectsMixedCurrencies() throws {
    let usd = try CurrencyCode(rawValue: "usd")
    let cny = try CurrencyCode(rawValue: "CNY")
    let first = Money(amount: Decimal(string: "0.1")!, currency: usd)
    let second = Money(amount: Decimal(string: "0.2")!, currency: usd)

    #expect(try first.adding(second).amount == Decimal(string: "0.3")!)
    #expect(usd.rawValue == "USD")
    #expect(throws: DomainModelError.self) {
        try first.adding(Money(amount: 1, currency: cny))
    }
    #expect(throws: DomainModelError.self) {
        try CurrencyCode(rawValue: "US")
    }
}

@Test
func tokenCountsRejectNegativeValuesAndOverflow() throws {
    #expect(throws: DomainModelError.self) {
        try TokenCount(rawValue: -1)
    }

    let maximum = try TokenCount(rawValue: .max)
    let one = try TokenCount(rawValue: 1)
    #expect(throws: DomainModelError.self) {
        try maximum.adding(one)
    }
    #expect(throws: DomainModelError.self) {
        try JSONDecoder().decode(TokenCount.self, from: Data("-1".utf8))
    }
}

@Test
func usagePercentPreservesAnomaliesForDiagnostics() {
    let aboveLimit = UsagePercent(rawValue: 101)
    let belowZero = UsagePercent(rawValue: -1)

    #expect(aboveLimit.isOutOfBounds)
    #expect(aboveLimit.displayValue == 100)
    #expect(belowZero.isOutOfBounds)
    #expect(belowZero.displayValue == 0)
}

@Test
func accountDeduplicationIncludesProviderScopeAndHierarchy() throws {
    let provider = try ProviderID(rawValue: "openai-primary")
    let sharedHierarchy = AccountHierarchy(
        remoteAccountReference: "remote-account",
        organizationReference: "organization",
        projectReference: "project"
    )
    let first = try AccountReference(
        id: AccountID(rawValue: "local-a"),
        providerID: provider,
        displayName: "Team API",
        scope: .organization,
        hierarchy: sharedHierarchy
    )
    let duplicate = try AccountReference(
        id: AccountID(rawValue: "local-b"),
        providerID: provider,
        displayName: "Renamed Team API",
        scope: .organization,
        hierarchy: sharedHierarchy
    )
    let personal = try AccountReference(
        id: AccountID(rawValue: "local-c"),
        providerID: provider,
        displayName: "Personal API",
        scope: .personal,
        hierarchy: sharedHierarchy
    )
    let anotherProject = try AccountReference(
        id: AccountID(rawValue: "local-d"),
        providerID: provider,
        displayName: "Other Project",
        scope: .organization,
        hierarchy: AccountHierarchy(
            remoteAccountReference: "remote-account",
            organizationReference: "organization",
            projectReference: "another-project"
        )
    )

    #expect(first.deduplicationKey == duplicate.deduplicationKey)
    #expect(first.deduplicationKey != personal.deduplicationKey)
    #expect(first.deduplicationKey != anotherProject.deduplicationKey)
}

@Test
func capabilityDeclarationsDoNotImplyUnsupportedOperations() throws {
    let descriptor = try ProviderDescriptor(
        id: ProviderID(rawValue: "deepseek-primary"),
        type: ProviderType(rawValue: "deepseek"),
        displayName: "DeepSeek",
        capabilities: ProviderCapabilities([.usage, .balance])
    )

    #expect(descriptor.capabilities.contains(.usage))
    #expect(descriptor.capabilities.contains(.balance))
    #expect(!descriptor.capabilities.contains(.plan))
    #expect(!descriptor.capabilities.contains(.cost))
}

@Test
func dailyPeriodUsesExplicitTimeZoneAcrossDaylightSavingBoundary() throws {
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let noon = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))
    )

    let period = try UsagePeriod.containing(
        noon,
        granularity: .day,
        calendar: calendar,
        timeZone: timeZone
    )

    #expect(period.timeZoneIdentifier == "America/Los_Angeles")
    #expect(period.interval.duration == 23 * 60 * 60)
    #expect(calendar.component(.day, from: period.interval.start) == 8)
    #expect(calendar.component(.day, from: period.interval.end) == 9)
}

@Test
func monthlyPeriodUsesRequestedAccountTimeZone() throws {
    let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let instant = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 23))
    )

    let period = try UsagePeriod.containing(
        instant,
        granularity: .month,
        calendar: calendar,
        timeZone: timeZone
    )

    #expect(calendar.component(.month, from: period.interval.start) == 8)
    #expect(calendar.component(.day, from: period.interval.start) == 1)
    #expect(calendar.component(.month, from: period.interval.end) == 9)
    #expect(calendar.component(.day, from: period.interval.end) == 1)
}

@Test
func costAndSourceKeepOfficialAndEstimatedSemanticsDistinct() throws {
    let provider = try ProviderID(rawValue: "openai-primary")
    let account = try AccountID(rawValue: "account")
    let timeZone = try #require(TimeZone(identifier: "UTC"))
    let period = try UsagePeriod.containing(
        Date(timeIntervalSince1970: 0),
        granularity: .day,
        calendar: Calendar(identifier: .gregorian),
        timeZone: timeZone
    )
    let official = try DataSource(kind: .official, identifier: "official_cost_api")
    let estimated = try DataSource(kind: .estimated, identifier: "pricing_catalog_v1")
    let money = Money(
        amount: Decimal(string: "28.46")!,
        currency: try CurrencyCode(rawValue: "USD")
    )

    let officialCost = CostSnapshot(
        providerID: provider,
        accountID: account,
        period: period,
        money: money,
        metadata: ObservationMetadata(source: official, updatedAt: .distantPast, isStale: false)
    )
    let estimatedCost = CostSnapshot(
        providerID: provider,
        accountID: account,
        period: period,
        money: money,
        metadata: ObservationMetadata(source: estimated, updatedAt: .distantPast, isStale: false)
    )

    #expect(!officialCost.isEstimated)
    #expect(estimatedCost.isEstimated)
}

@Test
func separateAggregatesRoundTripWithoutLosingCurrencyOrTimeZone() throws {
    let provider = try ProviderID(rawValue: "minimax-primary")
    let account = try AccountID(rawValue: "account")
    let source = try DataSource(kind: .official, identifier: "token_plan_api")
    let metadata = ObservationMetadata(
        source: source,
        updatedAt: Date(timeIntervalSince1970: 1_786_403_600),
        isStale: false
    )
    let plan = try PlanWindow(
        providerID: provider,
        accountID: account,
        planName: "Token Plan",
        limitIdentifier: "five-hour",
        usedPercent: UsagePercent(rawValue: 42),
        windowDurationMinutes: 300,
        resetsAt: Date(timeIntervalSince1970: 1_786_415_940),
        timeZoneIdentifier: "Asia/Shanghai",
        metadata: metadata
    )

    let encoded = try JSONEncoder().encode(plan)
    let decoded = try JSONDecoder().decode(PlanWindow.self, from: encoded)

    #expect(decoded == plan)
    #expect(decoded.windowDurationMinutes == 300)
    #expect(decoded.timeZoneIdentifier == "Asia/Shanghai")
}
