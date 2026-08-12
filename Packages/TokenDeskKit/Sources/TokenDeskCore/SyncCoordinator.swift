import Foundation

/// Bounded exponential-backoff settings for idempotent Provider reads.
public struct SyncRetryPolicy: Equatable, Sendable {
    /// Total attempts, including the initial request.
    public let maximumAttempts: Int
    /// Initial retry delay before exponential growth.
    public let baseDelaySeconds: Double
    /// Upper bound for a computed backoff delay.
    public let maximumDelaySeconds: Double
    /// Maximum positive random jitter as a fraction of the computed delay.
    public let jitterFraction: Double

    /// Creates a normalized policy, clamping invalid bounds to safe values.
    public init(
        maximumAttempts: Int = 3,
        baseDelaySeconds: Double = 1,
        maximumDelaySeconds: Double = 30 * 60,
        jitterFraction: Double = 0.2
    ) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.baseDelaySeconds = max(0, baseDelaySeconds)
        self.maximumDelaySeconds = max(0, maximumDelaySeconds)
        self.jitterFraction = min(max(0, jitterFraction), 1)
    }

    func delay(attempt: Int, error: ConnectorError, randomUnit: Double) -> Duration {
        if case .rateLimited(let retryAfter?) = error {
            return retryAfter
        }
        let exponential = baseDelaySeconds * pow(2, Double(max(0, attempt - 1)))
        let capped = min(maximumDelaySeconds, exponential)
        let jitter = capped * jitterFraction * min(max(0, randomUnit), 1)
        return .seconds(capped + jitter)
    }
}

/// Terminal outcome for one independently synchronized Provider.
public enum ProviderSyncStatus: Equatable, Sendable {
    case succeeded
    case failed(ConnectorError)
    case persistenceFailed
    case cancelled
}

/// Provider outcome and observed retry count from one synchronization run.
public struct ProviderSyncResult: Equatable, Sendable {
    /// Configured Provider instance that produced the result.
    public let providerID: ProviderID
    /// Normalized success, failure, or cancellation state.
    public let status: ProviderSyncStatus
    /// Maximum request attempts used by any operation for this Provider.
    public let attempts: Int

    /// Creates one Provider result.
    public init(providerID: ProviderID, status: ProviderSyncStatus, attempts: Int) {
        self.providerID = providerID
        self.status = status
        self.attempts = attempts
    }
}

/// Timing and per-Provider outcomes for one synchronization run.
public struct SyncReport: Equatable, Sendable {
    /// Instant immediately before Provider tasks were created.
    public let startedAt: Date
    /// Instant after every Provider task reached a terminal state.
    public let completedAt: Date
    /// Stable Provider-ID-ordered independent outcomes.
    public let providers: [ProviderSyncResult]

    /// Creates a completed report.
    public init(startedAt: Date, completedAt: Date, providers: [ProviderSyncResult]) {
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.providers = providers
    }
}

/// Coordinates cancellable Provider-parallel synchronization and isolated failure handling.
public actor SyncCoordinator {
    /// Cancellation-aware delay hook used by retry backoff.
    public typealias Sleeper = @Sendable (Duration) async throws -> Void
    /// Unit-interval random source used to make jitter deterministic in tests.
    public typealias RandomUnit = @Sendable () -> Double
    /// Clock hook used for report timestamps.
    public typealias Now = @Sendable () -> Date

    private let registry: ProviderConnectorRegistry
    private let repository: any ProviderSyncRepository
    private let retryPolicy: SyncRetryPolicy
    private let sleeper: Sleeper
    private let randomUnit: RandomUnit
    private let now: Now
    private var activeTask: Task<SyncReport, Never>?
    private var activeID: UUID?

    private struct RetryFailure: Error, Sendable {
        let error: ConnectorError
        let attempts: Int
    }

    /// Creates a coordinator from protocol-only connector and persistence dependencies.
    public init(
        registry: ProviderConnectorRegistry,
        repository: any ProviderSyncRepository,
        retryPolicy: SyncRetryPolicy = SyncRetryPolicy(),
        sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) },
        randomUnit: @escaping RandomUnit = { Double.random(in: 0...1) },
        now: @escaping Now = Date.init
    ) {
        self.registry = registry
        self.repository = repository
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
        self.randomUnit = randomUnit
        self.now = now
    }

    /// Starts a user-requested sync, cancelling any older run before it can write more data.
    public func manualSync(
        accountsByProvider: [ProviderID: [AccountReference]],
        interval: DateInterval,
        capabilities requestedCapabilities: Set<ProviderCapability>? = nil
    ) async -> SyncReport {
        activeTask?.cancel()
        let runID = UUID()
        let connectors = await registry.allConnectors().filter { connector in
            guard let requestedCapabilities else { return true }
            return ProviderCapability.allCases.contains {
                requestedCapabilities.contains($0)
                    && connector.descriptor.capabilities.contains($0)
            }
        }
        let startedAt = now()
        let repository = repository
        let policy = retryPolicy
        let sleeper = sleeper
        let randomUnit = randomUnit
        let now = now
        let task = Task {
            let results = await Self.synchronizeProviders(
                connectors,
                accountsByProvider: accountsByProvider,
                interval: interval,
                requestedCapabilities: requestedCapabilities,
                repository: repository,
                policy: policy,
                sleeper: sleeper,
                randomUnit: randomUnit
            )
            return SyncReport(
                startedAt: startedAt,
                completedAt: now(),
                providers: results.sorted { $0.providerID.rawValue < $1.providerID.rawValue }
            )
        }
        activeTask = task
        activeID = runID
        let report = await task.value
        if activeID == runID {
            activeTask = nil
            activeID = nil
        }
        return report
    }

    /// Cancels the currently active synchronization run, if present.
    public func cancel() {
        activeTask?.cancel()
    }

    private static func synchronizeProviders(
        _ connectors: [any ProviderConnector],
        accountsByProvider: [ProviderID: [AccountReference]],
        interval: DateInterval,
        requestedCapabilities: Set<ProviderCapability>?,
        repository: any ProviderSyncRepository,
        policy: SyncRetryPolicy,
        sleeper: @escaping Sleeper,
        randomUnit: @escaping RandomUnit
    ) async -> [ProviderSyncResult] {
        await withTaskGroup(of: ProviderSyncResult.self) { group in
            for connector in connectors {
                let accounts = accountsByProvider[connector.descriptor.id] ?? []
                group.addTask {
                    await synchronizeProvider(
                        connector,
                        accounts: accounts,
                        interval: interval,
                        requestedCapabilities: requestedCapabilities,
                        repository: repository,
                        policy: policy,
                        sleeper: sleeper,
                        randomUnit: randomUnit
                    )
                }
            }

            var results: [ProviderSyncResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private static func synchronizeProvider(
        _ connector: any ProviderConnector,
        accounts: [AccountReference],
        interval: DateInterval,
        requestedCapabilities: Set<ProviderCapability>?,
        repository: any ProviderSyncRepository,
        policy: SyncRetryPolicy,
        sleeper: @escaping Sleeper,
        randomUnit: @escaping RandomUnit
    ) async -> ProviderSyncResult {
        var maximumAttempts = 1
        let shouldFetch: (ProviderCapability) -> Bool = { capability in
            connector.descriptor.capabilities.contains(capability)
                && (requestedCapabilities?.contains(capability) ?? true)
        }
        let hasRequestedCapability = ProviderCapability.allCases.contains(where: shouldFetch)
        guard hasRequestedCapability else {
            return ProviderSyncResult(
                providerID: connector.descriptor.id,
                status: .succeeded,
                attempts: maximumAttempts
            )
        }
        do {
            for account in accounts {
                let (_, validationAttempts) = try await retry(
                    policy: policy,
                    sleeper: sleeper,
                    randomUnit: randomUnit
                ) {
                    try await connector.validateCredentials(for: account)
                }
                maximumAttempts = max(maximumAttempts, validationAttempts)

                if shouldFetch(.plan) {
                    let (result, attempts) = try await retry(
                        policy: policy,
                        sleeper: sleeper,
                        randomUnit: randomUnit
                    ) { try await connector.fetchPlan(for: account) }
                    maximumAttempts = max(maximumAttempts, attempts)
                    try Task.checkCancellation()
                    if result.state == .available { try repository.savePlans(result.values) }
                }
                if shouldFetch(.usage) {
                    let (result, attempts) = try await retry(
                        policy: policy,
                        sleeper: sleeper,
                        randomUnit: randomUnit
                    ) { try await connector.fetchUsage(for: account, in: interval) }
                    maximumAttempts = max(maximumAttempts, attempts)
                    try Task.checkCancellation()
                    if result.state == .available { try repository.saveUsage(result.values) }
                }
                if shouldFetch(.cost) {
                    let (result, attempts) = try await retry(
                        policy: policy,
                        sleeper: sleeper,
                        randomUnit: randomUnit
                    ) { try await connector.fetchCosts(for: account, in: interval) }
                    maximumAttempts = max(maximumAttempts, attempts)
                    try Task.checkCancellation()
                    if result.state == .available { try repository.saveCosts(result.values) }
                }
                if shouldFetch(.balance) {
                    let (result, attempts) = try await retry(
                        policy: policy,
                        sleeper: sleeper,
                        randomUnit: randomUnit
                    ) { try await connector.fetchBalance(for: account) }
                    maximumAttempts = max(maximumAttempts, attempts)
                    try Task.checkCancellation()
                    if result.state == .available { try repository.saveBalances(result.values) }
                }
            }
            return ProviderSyncResult(
                providerID: connector.descriptor.id,
                status: .succeeded,
                attempts: maximumAttempts
            )
        } catch is CancellationError {
            return ProviderSyncResult(
                providerID: connector.descriptor.id,
                status: .cancelled,
                attempts: maximumAttempts
            )
        } catch let failure as RetryFailure {
            return ProviderSyncResult(
                providerID: connector.descriptor.id,
                status: .failed(failure.error),
                attempts: max(maximumAttempts, failure.attempts)
            )
        } catch {
            return ProviderSyncResult(
                providerID: connector.descriptor.id,
                status: .persistenceFailed,
                attempts: maximumAttempts
            )
        }
    }

    private static func retry<Value: Sendable>(
        policy: SyncRetryPolicy,
        sleeper: @escaping Sleeper,
        randomUnit: @escaping RandomUnit,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> (Value, Int) {
        var attempt = 1
        while true {
            try Task.checkCancellation()
            do {
                return (try await operation(), attempt)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ConnectorError {
                guard error.isRetryable, attempt < policy.maximumAttempts else {
                    throw RetryFailure(error: error, attempts: attempt)
                }
                let delay = policy.delay(
                    attempt: attempt,
                    error: error,
                    randomUnit: randomUnit()
                )
                attempt += 1
                try await sleeper(delay)
            }
        }
    }
}
