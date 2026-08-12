import Foundation
import TokenDeskCore

let fixtureInterval = DateInterval(
    start: Date(timeIntervalSince1970: 1_768_435_200),
    end: Date(timeIntervalSince1970: 1_768_521_600)
)
let fixtureNow: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_768_521_600) }

func makeDescriptor(
    id: String,
    type: String,
    capabilities: Set<ProviderCapability>
) throws -> ProviderDescriptor {
    try ProviderDescriptor(
        id: ProviderID(rawValue: id),
        type: ProviderType(rawValue: type),
        displayName: type.capitalized,
        capabilities: ProviderCapabilities(capabilities)
    )
}

func makeAccountAndCredential(
    descriptor: ProviderDescriptor,
    scope: AccountScope = .personal,
    workspace: String? = nil
) throws -> (AccountReference, StaticCredentialStore) {
    let reference = try CredentialReference(rawValue: "credential-fixture")
    let account = try AccountReference(
        id: AccountID(rawValue: "fixture-account"),
        providerID: descriptor.id,
        displayName: "Fixture Account",
        scope: scope,
        hierarchy: AccountHierarchy(workspaceReference: workspace),
        credentialReference: reference
    )
    return (
        account,
        try StaticCredentialStore(reference: reference, value: "fixture-redacted")
    )
}

final class InMemoryLocalUsageRepository: LocallyAggregatedUsageRepository, @unchecked Sendable {
    private struct Key: Hashable {
        let providerID: ProviderID
        let accountID: AccountID
        let projectReference: String?
        let workspaceReference: String?
        let model: String
        let start: Date
    }

    private let lock = NSLock()
    private var buckets: [Key: TokenUsageBucket] = [:]

    func addLocallyAggregatedUsage(_ usage: [TokenUsageBucket]) throws {
        lock.lock()
        defer { lock.unlock() }
        for bucket in usage {
            let key = Key(
                providerID: bucket.providerID,
                accountID: bucket.accountID,
                projectReference: bucket.projectReference,
                workspaceReference: bucket.workspaceReference,
                model: bucket.model,
                start: bucket.period.interval.start
            )
            guard let current = buckets[key] else {
                buckets[key] = bucket
                continue
            }
            buckets[key] = try TokenUsageBucket(
                providerID: bucket.providerID,
                accountID: bucket.accountID,
                projectReference: bucket.projectReference,
                workspaceReference: bucket.workspaceReference,
                model: bucket.model,
                granularity: bucket.granularity,
                period: bucket.period,
                tokens: TokenBreakdown(
                    input: try current.tokens.input.adding(bucket.tokens.input),
                    output: try current.tokens.output.adding(bucket.tokens.output),
                    cachedInput: try current.tokens.cachedInput.adding(bucket.tokens.cachedInput),
                    cacheWrite: try current.tokens.cacheWrite.adding(bucket.tokens.cacheWrite)
                ),
                metadata: bucket.metadata
            )
        }
    }

    func cachedUsage(
        for account: AccountReference,
        in interval: DateInterval,
        granularity: UsageGranularity
    ) throws -> [TokenUsageBucket] {
        lock.lock()
        defer { lock.unlock() }
        return buckets.values.filter {
            $0.providerID == account.providerID && $0.accountID == account.id
                && $0.granularity == granularity && $0.period.interval.intersects(interval)
        }.sorted { $0.period.interval.start < $1.period.interval.start }
    }
}

final class StaticPricingCatalog: PricingCatalog, @unchecked Sendable {
    private let ruleValue: PricingRule

    init(providerType: ProviderType, currency: CurrencyCode, model: String) throws {
        ruleValue = try PricingRule(
            id: "fixture-pricing",
            providerType: providerType,
            modelMatch: model,
            currency: currency,
            region: "global",
            version: 1,
            effectiveFrom: Date(timeIntervalSince1970: 1_700_000_000),
            rates: TokenRates(input: 1, output: 5, cacheRead: 0.5, cacheWrite: 1),
            source: DataSource(kind: .official, identifier: "fixture_pricing_source"),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func upsert(_ rules: [PricingRule]) throws {}

    func rule(
        providerType: ProviderType,
        model: String,
        currency: CurrencyCode,
        region: String,
        effectiveAt: Date
    ) throws -> PricingRule? {
        guard ruleValue.providerType == providerType, ruleValue.currency == currency,
            ruleValue.matches(model: model, region: region), ruleValue.isEffective(at: effectiveAt)
        else { return nil }
        return ruleValue
    }
}
