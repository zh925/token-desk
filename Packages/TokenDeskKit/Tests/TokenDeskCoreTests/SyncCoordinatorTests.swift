import Foundation
import Testing
import TokenDeskCore

@Test
func syncRunsProvidersConcurrentlyAndIsolatesTheirWrites() async throws {
    let probe = ConcurrencyProbe()
    let first = try makeSyncConnector(id: "first", behavior: SyncBehavior(probe: probe))
    let second = try makeSyncConnector(id: "second", behavior: SyncBehavior(probe: probe))
    let registry = try ProviderConnectorRegistry(connectors: [first, second])
    let repository = SyncRepositorySpy()
    let coordinator = SyncCoordinator(registry: registry, repository: repository)

    let report = await coordinator.manualSync(
        accountsByProvider: [
            first.descriptor.id: [try makeSyncAccount(providerID: first.descriptor.id)],
            second.descriptor.id: [try makeSyncAccount(providerID: second.descriptor.id)],
        ],
        interval: DateInterval(start: .distantPast, duration: 1)
    )

    #expect(await probe.maximumActive == 2)
    #expect(report.providers.map(\.status) == [.succeeded, .succeeded])
    #expect(repository.usageWriteCount == 2)
}

@Test
func syncRetriesNetworkAndRetryAfterButNeverRetriesAuthentication() async throws {
    let networkBehavior = SyncBehavior(failures: [.network])
    let authenticationBehavior = SyncBehavior(failures: [.authentication])
    let rateLimitBehavior = SyncBehavior(failures: [.rateLimited(retryAfter: .seconds(7))])
    let network = try makeSyncConnector(id: "network", behavior: networkBehavior)
    let authentication = try makeSyncConnector(
        id: "authentication", behavior: authenticationBehavior)
    let rateLimit = try makeSyncConnector(id: "rate-limit", behavior: rateLimitBehavior)
    let registry = try ProviderConnectorRegistry(
        connectors: [network, authentication, rateLimit]
    )
    let repository = SyncRepositorySpy()
    let sleeps = SleepRecorder()
    let coordinator = SyncCoordinator(
        registry: registry,
        repository: repository,
        retryPolicy: SyncRetryPolicy(
            maximumAttempts: 3,
            baseDelaySeconds: 1,
            maximumDelaySeconds: 30,
            jitterFraction: 0
        ),
        sleeper: { duration in
            await sleeps.record(duration)
            try Task.checkCancellation()
        },
        randomUnit: { 0 }
    )
    let connectors = [network, authentication, rateLimit]
    let accounts = try Dictionary(
        uniqueKeysWithValues: connectors.map { connector in
            (connector.descriptor.id, [try makeSyncAccount(providerID: connector.descriptor.id)])
        }
    )

    let report = await coordinator.manualSync(
        accountsByProvider: accounts,
        interval: DateInterval(start: .distantPast, duration: 1)
    )

    #expect(await networkBehavior.attempts == 2)
    #expect(await authenticationBehavior.attempts == 1)
    #expect(await rateLimitBehavior.attempts == 2)
    #expect(await sleeps.values.contains(.seconds(1)))
    #expect(await sleeps.values.contains(.seconds(7)))
    #expect(
        report.providers.first { $0.providerID == authentication.descriptor.id }?.status
            == .failed(.authentication)
    )
    #expect(repository.usageWriteCount == 2)
}

@Test
func syncRetriesServerFailureButNeverRetriesPermissionFailure() async throws {
    let serverBehavior = SyncBehavior(failures: [.server(statusCode: 500)])
    let permissionBehavior = SyncBehavior(failures: [.permissionDenied])
    let server = try makeSyncConnector(id: "server", behavior: serverBehavior)
    let permission = try makeSyncConnector(id: "permission", behavior: permissionBehavior)
    let registry = try ProviderConnectorRegistry(connectors: [server, permission])
    let repository = SyncRepositorySpy()
    let sleeps = SleepRecorder()
    let coordinator = SyncCoordinator(
        registry: registry,
        repository: repository,
        retryPolicy: SyncRetryPolicy(
            maximumAttempts: 3,
            baseDelaySeconds: 1,
            maximumDelaySeconds: 30,
            jitterFraction: 0
        ),
        sleeper: { duration in
            await sleeps.record(duration)
            try Task.checkCancellation()
        },
        randomUnit: { 0 }
    )
    let accounts = try Dictionary(
        uniqueKeysWithValues: [server, permission].map { connector in
            (connector.descriptor.id, [try makeSyncAccount(providerID: connector.descriptor.id)])
        }
    )

    let report = await coordinator.manualSync(
        accountsByProvider: accounts,
        interval: DateInterval(start: .distantPast, duration: 1)
    )

    #expect(await serverBehavior.attempts == 2)
    #expect(await permissionBehavior.attempts == 1)
    #expect(await sleeps.values == [.seconds(1)])
    #expect(
        report.providers.first { $0.providerID == server.descriptor.id }?.status == .succeeded
    )
    #expect(
        report.providers.first { $0.providerID == permission.descriptor.id }?.status
            == .failed(.permissionDenied)
    )
    #expect(repository.usageWriteCount == 1)
}

@Test
func oneFailedProviderDoesNotAffectTheOtherEightMVPProviders() async throws {
    let providerIDs = [
        "anthropic", "codex", "deepseek", "gemini", "glm", "kimi", "minimax", "openai",
        "openrouter",
    ]
    let failedProviderID = "openrouter"
    var connectors: [SyncTestConnector] = []
    var accounts: [ProviderID: [AccountReference]] = [:]

    for providerID in providerIDs {
        let behavior = SyncBehavior(
            failures: providerID == failedProviderID ? [.authentication] : []
        )
        let connector = try makeSyncConnector(id: providerID, behavior: behavior)
        connectors.append(connector)
        accounts[connector.descriptor.id] = [
            try makeSyncAccount(providerID: connector.descriptor.id)
        ]
    }

    let repository = SyncRepositorySpy()
    let coordinator = SyncCoordinator(
        registry: try ProviderConnectorRegistry(connectors: connectors),
        repository: repository
    )
    let report = await coordinator.manualSync(
        accountsByProvider: accounts,
        interval: DateInterval(start: .distantPast, duration: 1)
    )

    #expect(report.providers.count == 9)
    #expect(
        report.providers.first { $0.providerID.rawValue == failedProviderID }?.status
            == .failed(.authentication)
    )
    #expect(report.providers.filter { $0.status == .succeeded }.count == 8)
    #expect(repository.usageWriteCount == 8)
}

@Test
func cancellationStopsAnInFlightProviderBeforePersistence() async throws {
    let gate = StartGate()
    let behavior = SyncBehavior(delay: .seconds(60), startGate: gate)
    let connector = try makeSyncConnector(id: "cancel", behavior: behavior)
    let registry = try ProviderConnectorRegistry(connectors: [connector])
    let repository = SyncRepositorySpy()
    let coordinator = SyncCoordinator(registry: registry, repository: repository)
    let account = try makeSyncAccount(providerID: connector.descriptor.id)
    let task = Task {
        await coordinator.manualSync(
            accountsByProvider: [connector.descriptor.id: [account]],
            interval: DateInterval(start: .distantPast, duration: 1)
        )
    }

    await gate.waitUntilStarted()
    await coordinator.cancel()
    let report = await task.value

    #expect(report.providers.first?.status == .cancelled)
    #expect(repository.usageWriteCount == 0)
}

@Test
func scopedSyncSkipsConnectorsWithoutADueCapability() async throws {
    let behavior = SyncBehavior()
    let connector = try makeSyncConnector(id: "usage-only", behavior: behavior)
    let coordinator = SyncCoordinator(
        registry: try ProviderConnectorRegistry(connectors: [connector]),
        repository: SyncRepositorySpy()
    )
    let accounts = [
        connector.descriptor.id: [try makeSyncAccount(providerID: connector.descriptor.id)]
    ]
    let interval = DateInterval(start: .distantPast, duration: 1)

    let moneyReport = await coordinator.manualSync(
        accountsByProvider: accounts,
        interval: interval,
        capabilities: [.cost, .balance]
    )
    #expect(moneyReport.providers.isEmpty)
    #expect(await behavior.attempts == 0)

    let usageReport = await coordinator.manualSync(
        accountsByProvider: accounts,
        interval: interval,
        capabilities: [.usage]
    )
    #expect(usageReport.providers.count == 1)
    #expect(await behavior.attempts == 1)
}

private struct SyncTestConnector: ProviderConnector {
    let descriptor: ProviderDescriptor
    let behavior: SyncBehavior
    let usage: TokenUsageBucket

    func validateCredentials(for account: AccountReference) async throws {
        try Task.checkCancellation()
    }

    func fetchAccounts() async throws -> ConnectorReadResult<RemoteAccount> { .empty }

    func fetchPlan(for account: AccountReference) async throws -> ConnectorReadResult<PlanWindow> {
        .unsupported
    }

    func fetchUsage(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<TokenUsageBucket> {
        try await behavior.fetch()
        return .available([usage])
    }

    func fetchCosts(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<CostSnapshot> {
        .unsupported
    }

    func fetchBalance(
        for account: AccountReference
    ) async throws -> ConnectorReadResult<BalanceSnapshot> {
        .unsupported
    }

    func fetchHealth() async -> ConnectorHealth {
        ConnectorHealth(
            providerID: descriptor.id,
            state: .healthy,
            checkedAt: .distantPast
        )
    }
}

private actor SyncBehavior {
    private var failures: [ConnectorError]
    private let probe: ConcurrencyProbe?
    private let delay: Duration?
    private let startGate: StartGate?
    private(set) var attempts = 0

    init(
        failures: [ConnectorError] = [],
        probe: ConcurrencyProbe? = nil,
        delay: Duration? = nil,
        startGate: StartGate? = nil
    ) {
        self.failures = failures
        self.probe = probe
        self.delay = delay
        self.startGate = startGate
    }

    func fetch() async throws {
        attempts += 1
        if let startGate {
            await startGate.markStarted()
        }
        if let probe {
            try await probe.overlap()
        }
        if let delay {
            try await Task.sleep(for: delay)
        }
        if !failures.isEmpty {
            throw failures.removeFirst()
        }
        try Task.checkCancellation()
    }
}

private actor ConcurrencyProbe {
    private var active = 0
    private(set) var maximumActive = 0

    func overlap() async throws {
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(50))
    }
}

private actor SleepRecorder {
    private(set) var values: [Duration] = []

    func record(_ duration: Duration) {
        values.append(duration)
    }
}

private actor StartGate {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        started = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private final class SyncRepositorySpy: ProviderSyncRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var storedUsageWriteCount = 0

    var usageWriteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedUsageWriteCount
    }

    func savePlans(_ plans: [PlanWindow]) throws {}

    func saveUsage(_ usage: [TokenUsageBucket]) throws {
        lock.lock()
        storedUsageWriteCount += usage.count
        lock.unlock()
    }

    func saveCosts(_ costs: [CostSnapshot]) throws {}

    func saveBalances(_ balances: [BalanceSnapshot]) throws {}
}

private func makeSyncConnector(id: String, behavior: SyncBehavior) throws -> SyncTestConnector {
    let descriptor = try ProviderDescriptor(
        id: ProviderID(rawValue: id),
        type: ProviderType(rawValue: "fixture"),
        displayName: id,
        capabilities: ProviderCapabilities([.usage])
    )
    let account = try AccountID(rawValue: "account")
    let period = try UsagePeriod(
        interval: DateInterval(start: .distantPast, duration: 1),
        timeZoneIdentifier: "UTC"
    )
    let usage = try TokenUsageBucket(
        providerID: descriptor.id,
        accountID: account,
        model: "fixture-model",
        granularity: .minute,
        period: period,
        tokens: TokenBreakdown(input: TokenCount(rawValue: 1), output: .zero),
        metadata: ObservationMetadata(
            source: DataSource(kind: .official, identifier: "fixture"),
            updatedAt: .distantPast,
            isStale: false
        )
    )
    return SyncTestConnector(descriptor: descriptor, behavior: behavior, usage: usage)
}

private func makeSyncAccount(providerID: ProviderID) throws -> AccountReference {
    try AccountReference(
        id: AccountID(rawValue: "account"),
        providerID: providerID,
        displayName: "Fixture Account",
        scope: .personal
    )
}
