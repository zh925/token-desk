import Foundation
import GRDB
import TokenDeskCore

/// SQLite-backed, version-aware price lookup with exact-model and region fallbacks.
public final class GRDBPricingCatalog: PricingCatalog, @unchecked Sendable {
    private let writer: any DatabaseWriter

    /// Creates a catalog over a migrated GRDB writer.
    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    /// Atomically inserts new rules or replaces matching stable identifiers.
    public func upsert(_ rules: [PricingRule]) throws {
        try writer.write { database in
            for rule in rules {
                try database.execute(
                    sql: """
                        INSERT INTO pricing_rules (
                            id, provider_type, model_match, currency, region, version,
                            effective_from, effective_to, input_per_million_decimal,
                            output_per_million_decimal, cache_read_per_million_decimal,
                            cache_write_per_million_decimal, source, updated_at, source_kind
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            provider_type = excluded.provider_type,
                            model_match = excluded.model_match,
                            currency = excluded.currency,
                            region = excluded.region,
                            version = excluded.version,
                            effective_from = excluded.effective_from,
                            effective_to = excluded.effective_to,
                            input_per_million_decimal = excluded.input_per_million_decimal,
                            output_per_million_decimal = excluded.output_per_million_decimal,
                            cache_read_per_million_decimal = excluded.cache_read_per_million_decimal,
                            cache_write_per_million_decimal = excluded.cache_write_per_million_decimal,
                            source = excluded.source,
                            updated_at = excluded.updated_at,
                            source_kind = excluded.source_kind
                        """,
                    arguments: [
                        rule.id,
                        rule.providerType.rawValue,
                        rule.modelMatch,
                        rule.currency.rawValue,
                        rule.region,
                        rule.version,
                        PersistenceCodec.date(rule.effectiveFrom),
                        rule.effectiveTo.map(PersistenceCodec.date),
                        PersistenceCodec.decimal(rule.rates.input),
                        PersistenceCodec.decimal(rule.rates.output),
                        PersistenceCodec.decimal(rule.rates.cacheRead),
                        PersistenceCodec.decimal(rule.rates.cacheWrite),
                        rule.source.identifier,
                        PersistenceCodec.date(rule.updatedAt),
                        rule.source.kind.rawValue,
                    ]
                )
            }
        }
    }

    /// Selects the most specific active model/region rule, then the newest version.
    public func rule(
        providerType: ProviderType,
        model: String,
        currency: CurrencyCode,
        region: String,
        effectiveAt: Date
    ) throws -> PricingRule? {
        try writer.read { database in
            guard
                let row = try Row.fetchOne(
                    database,
                    sql: """
                        SELECT * FROM pricing_rules
                        WHERE provider_type = ? AND currency = ?
                            AND model_match IN (?, '*') AND region IN (?, 'global')
                            AND effective_from <= ?
                            AND (effective_to IS NULL OR effective_to > ?)
                        ORDER BY
                            CASE WHEN model_match = ? THEN 0 ELSE 1 END,
                            CASE WHEN region = ? THEN 0 ELSE 1 END,
                            version DESC,
                            effective_from DESC
                        LIMIT 1
                        """,
                    arguments: [
                        providerType.rawValue,
                        currency.rawValue,
                        model,
                        region,
                        PersistenceCodec.date(effectiveAt),
                        PersistenceCodec.date(effectiveAt),
                        model,
                        region,
                    ]
                )
            else {
                return nil
            }
            return try Self.rule(from: row)
        }
    }

    private static func rule(from row: Row) throws -> PricingRule {
        let sourceKindRaw: String = row["source_kind"]
        guard let sourceKind = DataSourceKind(rawValue: sourceKindRaw) else {
            throw UsageRepositoryError.invalidStoredValue(field: "sourceKind")
        }
        guard
            let input = PersistenceCodec.decimal(row["input_per_million_decimal"] as String),
            let output = PersistenceCodec.decimal(row["output_per_million_decimal"] as String),
            let cacheRead = PersistenceCodec.decimal(
                row["cache_read_per_million_decimal"] as String
            ),
            let cacheWrite = PersistenceCodec.decimal(
                row["cache_write_per_million_decimal"] as String
            )
        else {
            throw UsageRepositoryError.invalidStoredValue(field: "pricingRate")
        }
        let effectiveToValue: String? = row["effective_to"]
        return try PricingRule(
            id: row["id"],
            providerType: ProviderType(rawValue: row["provider_type"]),
            modelMatch: row["model_match"],
            currency: CurrencyCode(rawValue: row["currency"]),
            region: row["region"],
            version: row["version"],
            effectiveFrom: try PersistenceCodec.date(row["effective_from"]),
            effectiveTo: try effectiveToValue.map(PersistenceCodec.date),
            rates: TokenRates(
                input: input,
                output: output,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite
            ),
            source: DataSource(kind: sourceKind, identifier: row["source"]),
            updatedAt: try PersistenceCodec.date(row["updated_at"])
        )
    }
}
