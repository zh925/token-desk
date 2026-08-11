import Foundation
import GRDB

/// Opens and migrates Token Desk's local SQLite database.
public enum TokenDeskDatabase {
    /// Opens a file-backed database pool configured for concurrent reads and serialized writes.
    public static func open(atPath path: String) throws -> DatabasePool {
        let pool = try DatabasePool(path: path, configuration: configuration)
        try TokenDeskDatabaseMigrator.migrate(pool)
        return pool
    }

    /// The shared connection policy for production and migration tests.
    public static var configuration: Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.journalMode = .wal
        configuration.busyMode = .timeout(5)
        return configuration
    }
}

/// Owns the explicit, forward-only SQLite migration chain.
public enum TokenDeskDatabaseMigrator {
    /// The ledger-only predecessor used to verify upgrades into schema v1.
    public static let bootstrapIdentifier = "v000_migrationLedger"
    /// The first application schema described by PRD section 20.
    public static let latestIdentifier = "v001_initialSchema"

    /// Runs every pending migration in registration order.
    public static func migrate(_ writer: any DatabaseWriter) throws {
        try migrator.migrate(writer)
    }

    /// Runs migrations through a specific registered version.
    ///
    /// This entry point exists for deterministic migration-chain tests and recovery tooling.
    public static func migrate(_ writer: any DatabaseWriter, upTo identifier: String) throws {
        try migrator.migrate(writer, upTo: identifier)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(bootstrapIdentifier) { database in
            try database.execute(
                sql: """
                    CREATE TABLE schema_migrations (
                        identifier TEXT PRIMARY KEY NOT NULL,
                        applied_at TEXT NOT NULL
                    ) STRICT
                    """
            )
            try recordMigration(bootstrapIdentifier, in: database)
        }
        migrator.registerMigration(latestIdentifier) { database in
            try createInitialSchema(in: database)
            try recordMigration(latestIdentifier, in: database)
        }
        return migrator
    }

    private static func recordMigration(_ identifier: String, in database: Database) throws {
        try database.execute(
            sql: "INSERT INTO schema_migrations (identifier, applied_at) VALUES (?, ?)",
            arguments: [identifier, utcTimestamp()]
        )
    }

    private static func utcTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func createInitialSchema(in database: Database) throws {
        try createProviders(in: database)
        try createAccounts(in: database)
        try createPlanSnapshots(in: database)
        try createUsageBuckets(in: database)
        try createCostBuckets(in: database)
        try createBalances(in: database)
        try createPricingRules(in: database)
        try createWeatherCache(in: database)
        try createAlertRules(in: database)
        try createAlertEvents(in: database)
        try createExportJobs(in: database)
        try createAppPreferences(in: database)
    }

    private static func createProviders(in database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE providers (
                    id TEXT PRIMARY KEY NOT NULL,
                    type TEXT NOT NULL,
                    display_name TEXT NOT NULL CHECK (length(trim(display_name)) > 0),
                    is_enabled INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0, 1)),
                    refresh_interval_seconds INTEGER NOT NULL CHECK (refresh_interval_seconds > 0),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                ) STRICT
                """
        )
        try database.execute(
            sql: "CREATE INDEX providers_enabled_idx ON providers (is_enabled, display_name)"
        )
    }

    private static func createAccounts(in database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE accounts (
                    id TEXT PRIMARY KEY NOT NULL,
                    provider_id TEXT NOT NULL,
                    display_name TEXT NOT NULL CHECK (length(trim(display_name)) > 0),
                    scope TEXT NOT NULL CHECK (scope IN ('personal', 'organization')),
                    deduplication_key TEXT NOT NULL,
                    remote_account_reference TEXT,
                    organization_reference TEXT,
                    project_reference TEXT,
                    workspace_reference TEXT,
                    credential_reference TEXT,
                    is_enabled INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0, 1)),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    FOREIGN KEY (provider_id) REFERENCES providers (id) ON DELETE CASCADE,
                    UNIQUE (provider_id, deduplication_key),
                    UNIQUE (id, provider_id)
                ) STRICT
                """
        )
        try database.execute(
            sql: "CREATE INDEX accounts_provider_enabled_idx ON accounts (provider_id, is_enabled)"
        )
    }

    private static func createPlanSnapshots(in database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE plan_snapshots (
                    id INTEGER PRIMARY KEY,
                    provider_id TEXT NOT NULL,
                    account_id TEXT NOT NULL,
                    plan_name TEXT NOT NULL,
                    limit_identifier TEXT NOT NULL,
                    used_percent_decimal TEXT NOT NULL,
                    window_duration_minutes INTEGER NOT NULL CHECK (window_duration_minutes > 0),
                    resets_at TEXT NOT NULL,
                    time_zone_identifier TEXT NOT NULL,
                    confidence_decimal TEXT,
                    source TEXT NOT NULL,
                    source_kind TEXT NOT NULL CHECK (
                        source_kind IN ('official', 'locallyAggregated', 'estimated', 'demonstration')
                    ),
                    updated_at TEXT NOT NULL,
                    is_stale INTEGER NOT NULL DEFAULT 0 CHECK (is_stale IN (0, 1)),
                    FOREIGN KEY (account_id, provider_id)
                        REFERENCES accounts (id, provider_id) ON DELETE CASCADE,
                    UNIQUE (provider_id, account_id, limit_identifier, resets_at, source)
                ) STRICT
                """
        )
        try database.execute(
            sql: """
                CREATE INDEX plan_snapshots_current_idx
                ON plan_snapshots (provider_id, account_id, resets_at DESC)
                """
        )
    }

    private static func createUsageBuckets(in database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE usage_buckets (
                    id INTEGER PRIMARY KEY,
                    provider_id TEXT NOT NULL,
                    account_id TEXT NOT NULL,
                    project_reference TEXT NOT NULL DEFAULT '',
                    model TEXT NOT NULL,
                    granularity TEXT NOT NULL CHECK (granularity IN ('minute', 'hour', 'day')),
                    bucket_start_at TEXT NOT NULL,
                    bucket_end_at TEXT NOT NULL,
                    time_zone_identifier TEXT NOT NULL,
                    input_tokens INTEGER NOT NULL CHECK (input_tokens >= 0),
                    output_tokens INTEGER NOT NULL CHECK (output_tokens >= 0),
                    cached_input_tokens INTEGER NOT NULL DEFAULT 0 CHECK (cached_input_tokens >= 0),
                    cache_write_tokens INTEGER NOT NULL DEFAULT 0 CHECK (cache_write_tokens >= 0),
                    source TEXT NOT NULL,
                    source_kind TEXT NOT NULL CHECK (
                        source_kind IN ('official', 'locallyAggregated', 'estimated', 'demonstration')
                    ),
                    updated_at TEXT NOT NULL,
                    is_stale INTEGER NOT NULL DEFAULT 0 CHECK (is_stale IN (0, 1)),
                    CHECK (bucket_start_at < bucket_end_at),
                    FOREIGN KEY (account_id, provider_id)
                        REFERENCES accounts (id, provider_id) ON DELETE CASCADE,
                    UNIQUE (
                        provider_id,
                        account_id,
                        project_reference,
                        model,
                        granularity,
                        bucket_start_at
                    )
                ) STRICT
                """
        )
        try database.execute(
            sql: """
                CREATE INDEX usage_buckets_range_idx
                ON usage_buckets (
                    provider_id,
                    account_id,
                    granularity,
                    bucket_start_at DESC
                )
                """
        )
        try database.execute(
            sql: """
                CREATE INDEX usage_buckets_retention_idx
                ON usage_buckets (granularity, bucket_start_at)
                """
        )
    }

    private static func createCostBuckets(in database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE cost_buckets (
                    id INTEGER PRIMARY KEY,
                    provider_id TEXT NOT NULL,
                    account_id TEXT NOT NULL,
                    project_reference TEXT NOT NULL DEFAULT '',
                    bucket_start_at TEXT NOT NULL,
                    bucket_end_at TEXT NOT NULL,
                    time_zone_identifier TEXT NOT NULL,
                    amount_decimal TEXT NOT NULL,
                    currency TEXT NOT NULL CHECK (
                        length(currency) = 3 AND currency = upper(currency)
                    ),
                    is_estimated INTEGER NOT NULL CHECK (is_estimated IN (0, 1)),
                    source TEXT NOT NULL,
                    source_kind TEXT NOT NULL CHECK (
                        source_kind IN ('official', 'locallyAggregated', 'estimated', 'demonstration')
                    ),
                    updated_at TEXT NOT NULL,
                    is_stale INTEGER NOT NULL DEFAULT 0 CHECK (is_stale IN (0, 1)),
                    CHECK (bucket_start_at < bucket_end_at),
                    FOREIGN KEY (account_id, provider_id)
                        REFERENCES accounts (id, provider_id) ON DELETE CASCADE,
                    UNIQUE (
                        provider_id,
                        account_id,
                        project_reference,
                        bucket_start_at,
                        bucket_end_at,
                        currency,
                        source
                    )
                ) STRICT
                """
        )
        try database.execute(
            sql: """
                CREATE INDEX cost_buckets_range_idx
                ON cost_buckets (provider_id, account_id, bucket_start_at DESC, currency)
                """
        )
    }

    private static func createBalances(in database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE balances (
                    id INTEGER PRIMARY KEY,
                    provider_id TEXT NOT NULL,
                    account_id TEXT NOT NULL,
                    available_amount_decimal TEXT NOT NULL,
                    currency TEXT NOT NULL CHECK (
                        length(currency) = 3 AND currency = upper(currency)
                    ),
                    observed_at TEXT NOT NULL,
                    source TEXT NOT NULL,
                    source_kind TEXT NOT NULL CHECK (
                        source_kind IN ('official', 'locallyAggregated', 'estimated', 'demonstration')
                    ),
                    updated_at TEXT NOT NULL,
                    is_stale INTEGER NOT NULL DEFAULT 0 CHECK (is_stale IN (0, 1)),
                    FOREIGN KEY (account_id, provider_id)
                        REFERENCES accounts (id, provider_id) ON DELETE CASCADE,
                    UNIQUE (provider_id, account_id, currency, observed_at, source)
                ) STRICT
                """
        )
        try database.execute(
            sql: """
                CREATE INDEX balances_latest_idx
                ON balances (provider_id, account_id, observed_at DESC)
                """
        )
    }

    private static func createPricingRules(in database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE pricing_rules (
                    id TEXT PRIMARY KEY NOT NULL,
                    provider_type TEXT NOT NULL,
                    model_match TEXT NOT NULL,
                    currency TEXT NOT NULL CHECK (
                        length(currency) = 3 AND currency = upper(currency)
                    ),
                    region TEXT NOT NULL,
                    version INTEGER NOT NULL CHECK (version > 0),
                    effective_from TEXT NOT NULL,
                    effective_to TEXT,
                    input_per_million_decimal TEXT NOT NULL,
                    output_per_million_decimal TEXT NOT NULL,
                    cache_read_per_million_decimal TEXT NOT NULL,
                    cache_write_per_million_decimal TEXT NOT NULL,
                    source TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    CHECK (effective_to IS NULL OR effective_from < effective_to),
                    UNIQUE (
                        provider_type,
                        model_match,
                        currency,
                        region,
                        effective_from,
                        version
                    )
                ) STRICT
                """
        )
        try database.execute(
            sql: """
                CREATE INDEX pricing_rules_lookup_idx
                ON pricing_rules (
                    provider_type,
                    model_match,
                    region,
                    effective_from DESC,
                    effective_to
                )
                """
        )
    }

    private static func createWeatherCache(in database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE weather_cache (
                    cache_slot INTEGER PRIMARY KEY DEFAULT 1 CHECK (cache_slot = 1),
                    location_key TEXT NOT NULL,
                    city_name TEXT NOT NULL,
                    latitude_decimal TEXT,
                    longitude_decimal TEXT,
                    observed_at TEXT NOT NULL,
                    temperature_decimal TEXT NOT NULL,
                    apparent_temperature_decimal TEXT,
                    precipitation_probability_decimal TEXT,
                    humidity_percent_decimal TEXT,
                    condition_code TEXT NOT NULL,
                    hourly_payload_json TEXT NOT NULL,
                    source TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                ) STRICT
                """
        )
        try database.execute(
            sql: "CREATE INDEX weather_cache_updated_idx ON weather_cache (updated_at DESC)"
        )
    }

    private static func createAlertRules(in database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE alert_rules (
                    id TEXT PRIMARY KEY NOT NULL,
                    provider_id TEXT,
                    account_id TEXT,
                    kind TEXT NOT NULL CHECK (
                        kind IN ('planPercent', 'budgetPercent', 'balanceFloor', 'syncFailure')
                    ),
                    threshold_decimal TEXT NOT NULL,
                    currency TEXT CHECK (
                        currency IS NULL OR (length(currency) = 3 AND currency = upper(currency))
                    ),
                    is_enabled INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0, 1)),
                    cooldown_seconds INTEGER NOT NULL CHECK (cooldown_seconds >= 0),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    CHECK (account_id IS NULL OR provider_id IS NOT NULL),
                    FOREIGN KEY (provider_id) REFERENCES providers (id) ON DELETE CASCADE,
                    FOREIGN KEY (account_id, provider_id)
                        REFERENCES accounts (id, provider_id) ON DELETE CASCADE
                ) STRICT
                """
        )
        try database.execute(
            sql: """
                CREATE INDEX alert_rules_active_idx
                ON alert_rules (is_enabled, kind, provider_id, account_id)
                """
        )
    }

    private static func createAlertEvents(in database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE alert_events (
                    id TEXT PRIMARY KEY NOT NULL,
                    rule_id TEXT NOT NULL,
                    state TEXT NOT NULL CHECK (state IN ('triggered', 'recovered', 'suppressed')),
                    observed_value_decimal TEXT,
                    triggered_at TEXT NOT NULL,
                    notified_at TEXT,
                    recovered_at TEXT,
                    source TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    FOREIGN KEY (rule_id) REFERENCES alert_rules (id) ON DELETE CASCADE
                ) STRICT
                """
        )
        try database.execute(
            sql: """
                CREATE INDEX alert_events_timeline_idx
                ON alert_events (rule_id, triggered_at DESC)
                """
        )
    }

    private static func createExportJobs(in database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE export_jobs (
                    id TEXT PRIMARY KEY NOT NULL,
                    provider_id TEXT,
                    account_id TEXT,
                    format TEXT NOT NULL CHECK (format IN ('csv', 'json')),
                    status TEXT NOT NULL CHECK (
                        status IN ('pending', 'running', 'completed', 'failed', 'cancelled')
                    ),
                    range_start_at TEXT NOT NULL,
                    range_end_at TEXT NOT NULL,
                    granularity TEXT CHECK (granularity IN ('minute', 'hour', 'day')),
                    scope_json TEXT NOT NULL,
                    destination_bookmark_reference TEXT,
                    result_summary_json TEXT,
                    error_category TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    CHECK (range_start_at < range_end_at),
                    CHECK (account_id IS NULL OR provider_id IS NOT NULL),
                    FOREIGN KEY (provider_id) REFERENCES providers (id) ON DELETE SET NULL,
                    FOREIGN KEY (account_id, provider_id)
                        REFERENCES accounts (id, provider_id) ON DELETE SET NULL
                ) STRICT
                """
        )
        try database.execute(
            sql: """
                CREATE INDEX export_jobs_status_idx
                ON export_jobs (status, created_at DESC)
                """
        )
    }

    private static func createAppPreferences(in database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE app_preferences (
                    key TEXT PRIMARY KEY NOT NULL,
                    value_json TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                ) STRICT
                """
        )
    }
}
