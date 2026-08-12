import Foundation
import GRDB
import Testing
import TokenDeskData

@Test
func emptyDatabaseMigratesToLatestSchema() throws {
    let database = try DatabaseQueue(configuration: TokenDeskDatabase.configuration)

    try TokenDeskDatabaseMigrator.migrate(database)
    try assertLatestSchema(in: database)

    let migrations = try database.read { database in
        try String.fetchAll(
            database,
            sql: "SELECT identifier FROM schema_migrations ORDER BY identifier"
        )
    }
    #expect(
        migrations == [
            TokenDeskDatabaseMigrator.bootstrapIdentifier,
            TokenDeskDatabaseMigrator.initialSchemaIdentifier,
            TokenDeskDatabaseMigrator.pricingProvenanceIdentifier,
            TokenDeskDatabaseMigrator.latestIdentifier,
        ]
    )
}

@Test
func pricingSchemaMigratesProviderDimensionsWithoutLosingUsage() throws {
    let database = try DatabaseQueue(configuration: TokenDeskDatabase.configuration)
    try TokenDeskDatabaseMigrator.migrate(
        database,
        upTo: TokenDeskDatabaseMigrator.pricingProvenanceIdentifier
    )
    let timestamp = "2026-08-12T00:00:00Z"
    try database.write { database in
        try insertProviderAndAccount(in: database, timestamp: timestamp)
        try database.execute(
            sql: """
                INSERT INTO usage_buckets (
                    provider_id, account_id, model, granularity, bucket_start_at,
                    bucket_end_at, time_zone_identifier, input_tokens, output_tokens,
                    source, source_kind, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                "provider-1", "account-1", "model", "minute", timestamp,
                "2026-08-12T00:01:00Z", "UTC", 12, 4, "response_usage",
                "locallyAggregated", timestamp,
            ]
        )
    }

    try TokenDeskDatabaseMigrator.migrate(database)

    let migrated = try database.read { database in
        try Row.fetchOne(database, sql: "SELECT * FROM usage_buckets")
    }
    #expect(migrated?["input_tokens"] as Int? == 12)
    #expect(migrated?["workspace_reference"] as String? == "")
}

@Test
func previousVersionMigratesForwardAndPreservesLedger() throws {
    let database = try DatabaseQueue(configuration: TokenDeskDatabase.configuration)
    try TokenDeskDatabaseMigrator.migrate(
        database,
        upTo: TokenDeskDatabaseMigrator.bootstrapIdentifier
    )

    let tablesBeforeUpgrade = try userTables(in: database)
    #expect(tablesBeforeUpgrade == ["grdb_migrations", "schema_migrations"])

    try TokenDeskDatabaseMigrator.migrate(database)
    try TokenDeskDatabaseMigrator.migrate(database)
    try assertLatestSchema(in: database)
}

@Test
func initialSchemaMigratesPricingProvenanceWithoutLosingRules() throws {
    let database = try DatabaseQueue(configuration: TokenDeskDatabase.configuration)
    try TokenDeskDatabaseMigrator.migrate(
        database,
        upTo: TokenDeskDatabaseMigrator.initialSchemaIdentifier
    )
    try database.write { database in
        try database.execute(
            sql: """
                INSERT INTO pricing_rules (
                    id, provider_type, model_match, currency, region, version,
                    effective_from, input_per_million_decimal, output_per_million_decimal,
                    cache_read_per_million_decimal, cache_write_per_million_decimal,
                    source, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                "legacy-v1", "example", "model", "USD", "global", 1,
                "2026-08-12T00:00:00Z", "1", "2", "0.5", "0.75",
                "official_pricing", "2026-08-12T00:00:00Z",
            ]
        )
    }

    try TokenDeskDatabaseMigrator.migrate(database)

    let provenance = try database.read { database in
        try String.fetchOne(
            database,
            sql: "SELECT source_kind FROM pricing_rules WHERE id = ?",
            arguments: ["legacy-v1"]
        )
    }
    #expect(provenance == "official")
}

@Test
func migrationIsAtomicWhenExistingSchemaConflicts() throws {
    let database = try DatabaseQueue(configuration: TokenDeskDatabase.configuration)
    try TokenDeskDatabaseMigrator.migrate(
        database,
        upTo: TokenDeskDatabaseMigrator.bootstrapIdentifier
    )
    try database.write { database in
        try database.execute(sql: "CREATE TABLE accounts (unexpected TEXT) STRICT")
    }

    #expect(throws: DatabaseError.self) {
        try TokenDeskDatabaseMigrator.migrate(database)
    }

    let applicationTables = try userTables(in: database).filter {
        !["accounts", "grdb_migrations", "schema_migrations"].contains($0)
    }
    #expect(applicationTables.isEmpty)

    let latestWasRecorded = try database.read { database in
        try Bool.fetchOne(
            database,
            sql: """
                SELECT EXISTS(
                    SELECT 1 FROM schema_migrations WHERE identifier = ?
                )
                """,
            arguments: [TokenDeskDatabaseMigrator.latestIdentifier]
        ) ?? false
    }
    #expect(!latestWasRecorded)
}

@Test
func foreignKeysAndUsageIdentityAreEnforced() throws {
    let database = try migratedDatabase()
    let timestamp = "2026-08-12T00:00:00Z"

    try database.write { database in
        try insertProviderAndAccount(in: database, timestamp: timestamp)
        try database.execute(
            sql: """
                INSERT INTO usage_buckets (
                    provider_id, account_id, model, granularity,
                    bucket_start_at, bucket_end_at, time_zone_identifier,
                    input_tokens, output_tokens, source, source_kind, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                "provider-1", "account-1", "gpt-example", "minute",
                timestamp, "2026-08-12T00:01:00Z", "UTC",
                12, 4, "official_usage_api", "official", timestamp,
            ]
        )
    }

    #expect(throws: DatabaseError.self) {
        try database.write { database in
            try database.execute(
                sql: """
                    INSERT INTO usage_buckets (
                        provider_id, account_id, model, granularity,
                        bucket_start_at, bucket_end_at, time_zone_identifier,
                        input_tokens, output_tokens, source, source_kind, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "provider-1", "account-1", "gpt-example", "minute",
                    timestamp, "2026-08-12T00:01:00Z", "UTC",
                    99, 1, "other_source", "official", timestamp,
                ]
            )
        }
    }

    #expect(throws: DatabaseError.self) {
        try database.write { database in
            try database.execute(
                sql: """
                    INSERT INTO balances (
                        provider_id, account_id, available_amount_decimal, currency,
                        observed_at, source, source_kind, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "missing-provider", "missing-account", "0", "USD",
                    timestamp, "official_balance_api", "official", timestamp,
                ]
            )
        }
    }
}

@Test
func monetaryColumnsUseTextStorageInsteadOfReal() throws {
    let database = try migratedDatabase()
    let expectedColumns: [String: Set<String>] = [
        "cost_buckets": ["amount_decimal"],
        "balances": [
            "available_amount_decimal",
            "total_credited_amount_decimal",
            "total_consumed_amount_decimal",
        ],
        "pricing_rules": [
            "input_per_million_decimal",
            "output_per_million_decimal",
            "cache_read_per_million_decimal",
            "cache_write_per_million_decimal",
        ],
        "alert_rules": ["threshold_decimal"],
        "alert_events": ["observed_value_decimal"],
    ]

    for (table, columns) in expectedColumns {
        let declaredTypes = try database.read { database in
            let rows = try Row.fetchAll(database, sql: "PRAGMA table_info(\(table))")
            return Dictionary(
                uniqueKeysWithValues: rows.map { row in
                    let name: String = row["name"]
                    let type: String = row["type"]
                    return (name, type)
                })
        }
        for column in columns {
            #expect(declaredTypes[column] == "TEXT")
        }
    }
}

@Test
func fileBackedDatabaseEnablesWALAndForeignKeys() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let pool = try TokenDeskDatabase.open(
        atPath: directory.appendingPathComponent("token-desk.sqlite").path
    )
    let settings = try pool.read { database in
        (
            try String.fetchOne(database, sql: "PRAGMA journal_mode"),
            try Int.fetchOne(database, sql: "PRAGMA foreign_keys")
        )
    }

    #expect(settings.0?.lowercased() == "wal")
    #expect(settings.1 == 1)
}

private func migratedDatabase() throws -> DatabaseQueue {
    let database = try DatabaseQueue(configuration: TokenDeskDatabase.configuration)
    try TokenDeskDatabaseMigrator.migrate(database)
    return database
}

private func userTables(in writer: any DatabaseWriter) throws -> [String] {
    try writer.read { database in
        try String.fetchAll(
            database,
            sql: """
                SELECT name
                FROM sqlite_schema
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
                ORDER BY name
                """
        )
    }
}

private func assertLatestSchema(in writer: any DatabaseWriter) throws {
    let expectedTables = [
        "accounts",
        "alert_events",
        "alert_rules",
        "app_preferences",
        "balances",
        "cost_buckets",
        "export_jobs",
        "grdb_migrations",
        "plan_snapshots",
        "pricing_rules",
        "providers",
        "schema_migrations",
        "usage_buckets",
        "weather_cache",
    ]
    #expect(try userTables(in: writer) == expectedTables)

    let foreignKeysEnabled = try writer.read { database in
        try Int.fetchOne(database, sql: "PRAGMA foreign_keys")
    }
    #expect(foreignKeysEnabled == 1)

    let indexes = try writer.read { database in
        try String.fetchAll(
            database,
            sql: """
                SELECT name
                FROM sqlite_schema
                WHERE type = 'index' AND name NOT LIKE 'sqlite_%'
                ORDER BY name
                """
        )
    }
    #expect(
        indexes == [
            "accounts_provider_enabled_idx",
            "alert_events_timeline_idx",
            "alert_rules_active_idx",
            "balances_latest_idx",
            "cost_buckets_range_idx",
            "export_jobs_status_idx",
            "plan_snapshots_current_idx",
            "pricing_rules_lookup_idx",
            "providers_enabled_idx",
            "usage_buckets_range_idx",
            "usage_buckets_retention_idx",
            "weather_cache_updated_idx",
        ]
    )

    let foreignKeyViolations = try writer.read { database in
        try Row.fetchAll(database, sql: "PRAGMA foreign_key_check")
    }
    #expect(foreignKeyViolations.isEmpty)
}

private func insertProviderAndAccount(in database: Database, timestamp: String) throws {
    try database.execute(
        sql: """
            INSERT INTO providers (
                id, type, display_name, refresh_interval_seconds, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
        arguments: ["provider-1", "openai", "Example Provider", 60, timestamp, timestamp]
    )
    try database.execute(
        sql: """
            INSERT INTO accounts (
                id, provider_id, display_name, scope, deduplication_key, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            "account-1", "provider-1", "Example Account", "personal", "local:account-1",
            timestamp, timestamp,
        ]
    )
}
