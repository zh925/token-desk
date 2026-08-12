import Foundation

/// Fixed local retention windows documented in the product data settings.
public struct HistoryRetentionPolicy: Equatable, Sendable {
    /// Number of days minute buckets remain available.
    public let minuteDays: Int
    /// Number of days hour buckets remain available.
    public let hourDays: Int
    /// Number of days daily buckets remain available.
    public let dayDays: Int

    /// Creates a retention policy with product defaults.
    public init(minuteDays: Int = 7, hourDays: Int = 90, dayDays: Int = 730) {
        self.minuteDays = minuteDays
        self.hourDays = hourDays
        self.dayDays = dayDays
    }

    /// The fixed policy currently exposed by Token Desk settings.
    public static let productDefault = HistoryRetentionPolicy()
}

/// User-selected history export scope. End dates are exclusive.
public struct HistoryExportRequest: Equatable, Sendable {
    /// End-exclusive UTC interval included by the export.
    public let interval: DateInterval
    /// Optional configured Provider scope.
    public let providerID: ProviderID?
    /// Optional local account scope.
    public let accountID: AccountID?
    /// Optional exact project filter, used for selection but never exported.
    public let projectReference: String?
    /// Stored Token granularities selected by the user.
    public let granularities: Set<UsageGranularity>

    /// Creates a normalized export scope.
    public init(
        interval: DateInterval,
        providerID: ProviderID? = nil,
        accountID: AccountID? = nil,
        projectReference: String? = nil,
        granularities: Set<UsageGranularity> = [.minute, .hour, .day]
    ) {
        self.interval = interval
        self.providerID = providerID
        self.accountID = accountID
        let normalizedProject = projectReference?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.projectReference = normalizedProject?.isEmpty == false ? normalizedProject : nil
        self.granularities = granularities
    }
}

/// Whitelisted export bytes and their non-sensitive summary.
public struct HistoryExportPayload: Equatable, Sendable {
    /// Complete CSV or JSON bytes ready for the save-panel boundary.
    public let data: Data
    /// Number of whitelisted usage and cost records in the payload.
    public let recordCount: Int

    /// Creates an export payload and its summary.
    public init(data: Data, recordCount: Int) {
        self.data = data
        self.recordCount = recordCount
    }
}

/// Row counts and on-disk bytes displayed without exposing database paths.
public struct HistoryStorageSnapshot: Equatable, Sendable {
    /// SQLite page allocation estimate, excluding filesystem paths.
    public let databaseBytes: Int64
    /// Number of retained Token usage rows.
    public let usageRows: Int
    /// Number of retained cost rows.
    public let costRows: Int
    /// Number of retained plan-window rows.
    public let planRows: Int
    /// Number of retained balance rows.
    public let balanceRows: Int
    /// Policy applied to stored Token granularities.
    public let retentionPolicy: HistoryRetentionPolicy

    /// Creates a non-sensitive storage summary.
    public init(
        databaseBytes: Int64,
        usageRows: Int,
        costRows: Int,
        planRows: Int,
        balanceRows: Int,
        retentionPolicy: HistoryRetentionPolicy = .productDefault
    ) {
        self.databaseBytes = databaseBytes
        self.usageRows = usageRows
        self.costRows = costRows
        self.planRows = planRows
        self.balanceRows = balanceRows
        self.retentionPolicy = retentionPolicy
    }

    /// Total history rows represented by the visible categories.
    public var historyRows: Int { usageRows + costRows + planRows + balanceRows }
}

/// Confirmed history deletion boundary. Provider and account settings are retained.
public enum HistoryClearScope: Equatable, Sendable {
    case provider(ProviderID)
    case all
}

/// Counts returned after one transactional clear operation.
public struct HistoryClearReport: Equatable, Sendable {
    /// Token usage rows removed.
    public let deletedUsageRows: Int
    /// Cost rows removed.
    public let deletedCostRows: Int
    /// Plan-window rows removed.
    public let deletedPlanRows: Int
    /// Balance rows removed.
    public let deletedBalanceRows: Int
    /// Alert history rows removed without deleting alert settings.
    public let deletedAlertEventRows: Int

    /// Creates the result of one committed history clear transaction.
    public init(
        deletedUsageRows: Int,
        deletedCostRows: Int,
        deletedPlanRows: Int,
        deletedBalanceRows: Int,
        deletedAlertEventRows: Int
    ) {
        self.deletedUsageRows = deletedUsageRows
        self.deletedCostRows = deletedCostRows
        self.deletedPlanRows = deletedPlanRows
        self.deletedBalanceRows = deletedBalanceRows
        self.deletedAlertEventRows = deletedAlertEventRows
    }

    /// Total rows removed across every history category.
    public var totalDeletedRows: Int {
        deletedUsageRows + deletedCostRows + deletedPlanRows + deletedBalanceRows
            + deletedAlertEventRows
    }
}

/// Database-facing history lifecycle boundary used by settings.
public protocol HistoryDataServicing: Sendable {
    /// Reads local allocation and row counts without returning a database path.
    func storageSnapshot() async throws -> HistoryStorageSnapshot
    /// Generates a cancellation-aware, whitelisted CSV or JSON payload.
    func makeExport(
        format: HistoryExportFormat,
        request: HistoryExportRequest
    ) async throws -> HistoryExportPayload
    /// Clears the confirmed history scope atomically while retaining settings and credentials.
    func clearHistory(scope: HistoryClearScope) async throws -> HistoryClearReport
}
