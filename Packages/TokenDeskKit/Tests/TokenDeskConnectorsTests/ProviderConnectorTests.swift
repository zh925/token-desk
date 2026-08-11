import Foundation
import Testing
import TokenDeskCore

private struct TestConnector: ProviderConnector {
    let descriptor: ProviderDescriptor
    var accounts: ConnectorReadResult<RemoteAccount> = .empty
    var plans: ConnectorReadResult<PlanWindow> = .unsupported
    var usage: ConnectorReadResult<TokenUsageBucket> = .unsupported
    var costs: ConnectorReadResult<CostSnapshot> = .unsupported
    var balances: ConnectorReadResult<BalanceSnapshot> = .unsupported
    var health: ConnectorHealth
    var accountsFailure: ConnectorError?
    var usageDelay: Duration?

    func validateCredentials(for account: AccountReference) async throws {
        try Task.checkCancellation()
    }

    func fetchAccounts() async throws -> ConnectorReadResult<RemoteAccount> {
        try Task.checkCancellation()
        if let accountsFailure {
            throw accountsFailure
        }
        return accounts
    }

    func fetchPlan(for account: AccountReference) async throws -> ConnectorReadResult<PlanWindow> {
        try Task.checkCancellation()
        return plans
    }

    func fetchUsage(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<TokenUsageBucket> {
        if let usageDelay {
            try await Task.sleep(for: usageDelay)
        }
        try Task.checkCancellation()
        return usage
    }

    func fetchCosts(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<CostSnapshot> {
        try Task.checkCancellation()
        return costs
    }

    func fetchBalance(
        for account: AccountReference
    ) async throws -> ConnectorReadResult<BalanceSnapshot> {
        try Task.checkCancellation()
        return balances
    }

    func fetchHealth() async -> ConnectorHealth {
        health
    }
}

final class ReferenceProviderConnectorContractTests: ProviderConnectorContractTestCase {
    func testReferenceConnectorSatisfiesContract() async throws {
        let descriptor = try makeDescriptor(id: "contract", capabilities: [.usage, .balance])
        let connector = TestConnector(
            descriptor: descriptor,
            usage: .notSynchronized,
            balances: .empty,
            health: ConnectorHealth(
                providerID: descriptor.id,
                state: .notSynchronized,
                checkedAt: .distantPast
            )
        )

        try await assertConnectorContract(
            connector,
            account: makeAccount(providerID: descriptor.id),
            interval: DateInterval(start: .distantPast, duration: 1)
        )
    }
}

@Test
func readResultsKeepUnsupportedEmptyNotSynchronizedAndZeroDistinct() throws {
    let providerID = try ProviderID(rawValue: "deepseek-primary")
    let accountID = try AccountID(rawValue: "personal")
    let zeroBalance = BalanceSnapshot(
        providerID: providerID,
        accountID: accountID,
        available: Money(
            amount: 0,
            currency: try CurrencyCode(rawValue: "CNY")
        ),
        metadata: ObservationMetadata(
            source: try DataSource(kind: .official, identifier: "balance_api"),
            updatedAt: .distantPast,
            isStale: false
        )
    )

    let available = ConnectorReadResult.available([zeroBalance])
    let normalizedEmpty = ConnectorReadResult<BalanceSnapshot>.available([])

    #expect(available.state == .available)
    #expect(available.values.first?.available.amount == 0)
    #expect(normalizedEmpty.state == .empty)
    #expect(ConnectorReadResult<BalanceSnapshot>.empty.state == .empty)
    #expect(ConnectorReadResult<BalanceSnapshot>.unsupported.state == .unsupported)
    #expect(ConnectorReadResult<BalanceSnapshot>.notSynchronized.state == .notSynchronized)
}

@Test
func permissionFailureIsNotFoldedIntoAnEmptyRead() async throws {
    let descriptor = try makeDescriptor(id: "permission", capabilities: [.usage])
    let connector = TestConnector(
        descriptor: descriptor,
        health: ConnectorHealth(
            providerID: descriptor.id,
            state: .unavailable,
            checkedAt: .distantPast,
            failure: .permissionDenied
        ),
        accountsFailure: .permissionDenied
    )

    do {
        _ = try await connector.fetchAccounts()
        Issue.record("Expected an explicit permission failure")
    } catch let error as ConnectorError {
        #expect(error == .permissionDenied)
    }
}

@Test
func normalizedErrorsExposeSafeRetryPolicy() {
    #expect(ConnectorError.network.isRetryable)
    #expect(ConnectorError.server(statusCode: 503).isRetryable)
    #expect(ConnectorError.rateLimited(retryAfter: .seconds(30)).isRetryable)
    #expect(!ConnectorError.authentication.isRetryable)
    #expect(!ConnectorError.permissionDenied.isRetryable)
    #expect(!ConnectorError.decoding.isRetryable)
    #expect(!ConnectorError.unsupported(capability: .plan).isRetryable)
    #expect(!ConnectorError.cancelled.isRetryable)
}

@Test
func connectorReadPreservesTaskCancellation() async throws {
    let descriptor = try makeDescriptor(id: "cancel", capabilities: [.usage])
    let connector = TestConnector(
        descriptor: descriptor,
        health: ConnectorHealth(
            providerID: descriptor.id,
            state: .synchronizing,
            checkedAt: .distantPast
        ),
        usageDelay: .seconds(60)
    )
    let account = try makeAccount(providerID: descriptor.id)
    let interval = DateInterval(start: .distantPast, duration: 1)
    let task = Task {
        try await connector.fetchUsage(for: account, in: interval)
    }

    task.cancel()

    do {
        _ = try await task.value
        Issue.record("Expected CancellationError")
    } catch is CancellationError {
        // Expected: cancellation is not converted into a retryable ConnectorError.
    }
}

@Test
func registryRejectsDuplicateConfiguredProviderIDs() async throws {
    let descriptor = try makeDescriptor(id: "duplicate", capabilities: [])
    let health = ConnectorHealth(
        providerID: descriptor.id,
        state: .healthy,
        checkedAt: .distantPast
    )
    let first = TestConnector(descriptor: descriptor, health: health)
    let second = TestConnector(descriptor: descriptor, health: health)
    let registry = try ProviderConnectorRegistry(connectors: [first])

    do {
        try await registry.register(second)
        Issue.record("Expected duplicate registration to fail")
    } catch let error as ProviderConnectorRegistryError {
        #expect(error == .duplicateProvider(descriptor.id))
    }
}

@Test
func registrySupportsExplicitRegistrationResolutionAndRemoval() async throws {
    let descriptor = try makeDescriptor(id: "lifecycle", capabilities: [.usage])
    let connector = TestConnector(
        descriptor: descriptor,
        health: ConnectorHealth(
            providerID: descriptor.id,
            state: .healthy,
            checkedAt: .distantPast
        )
    )
    let registry = try ProviderConnectorRegistry()

    try await registry.register(connector)

    #expect(await registry.connector(for: descriptor.id)?.descriptor == descriptor)
    #expect(await registry.allConnectors().map(\.descriptor.id) == [descriptor.id])
    #expect(await registry.remove(providerID: descriptor.id) != nil)
    #expect(await registry.connector(for: descriptor.id) == nil)
}

@Test
func healthSnapshotIsolatesAnUnavailableProvider() async throws {
    let healthyDescriptor = try makeDescriptor(id: "a-healthy", capabilities: [.usage])
    let failedDescriptor = try makeDescriptor(id: "b-failed", capabilities: [.balance])
    let healthy = TestConnector(
        descriptor: healthyDescriptor,
        health: ConnectorHealth(
            providerID: healthyDescriptor.id,
            state: .healthy,
            checkedAt: .distantPast,
            lastSuccessfulSyncAt: .distantPast
        )
    )
    let unavailable = TestConnector(
        descriptor: failedDescriptor,
        health: ConnectorHealth(
            providerID: failedDescriptor.id,
            state: .unavailable,
            checkedAt: .distantPast,
            failure: .authentication
        )
    )
    let registry = try ProviderConnectorRegistry(connectors: [unavailable, healthy])

    let snapshot = await registry.healthSnapshot()
    let descriptors = await registry.descriptors()

    #expect(snapshot.count == 2)
    #expect(snapshot[healthyDescriptor.id]?.state == .healthy)
    #expect(snapshot[failedDescriptor.id]?.failure == .authentication)
    #expect(descriptors.map(\.id) == [healthyDescriptor.id, failedDescriptor.id])
}

private func makeDescriptor(
    id: String,
    capabilities: Set<ProviderCapability>
) throws -> ProviderDescriptor {
    try ProviderDescriptor(
        id: ProviderID(rawValue: id),
        type: ProviderType(rawValue: "test-provider"),
        displayName: "Test Provider",
        capabilities: ProviderCapabilities(capabilities)
    )
}

private func makeAccount(providerID: ProviderID) throws -> AccountReference {
    try AccountReference(
        id: AccountID(rawValue: "test-account"),
        providerID: providerID,
        displayName: "Test Account",
        scope: .personal
    )
}
