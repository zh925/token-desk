import GRDB
import TokenDeskCore

/// Identifies the persistence boundary and its selected SQLite library.
public enum TokenDeskDataModule: Sendable {
    /// The stable module name used by diagnostics and baseline tests.
    public static let name = "TokenDeskData"

    /// The database engine selected by the architecture baseline.
    public static let databaseEngine = "GRDB"

    /// Confirms the GRDB product is linked without opening a database.
    public static var isDatabaseLibraryLinked: Bool {
        String(reflecting: DatabaseQueue.self).contains("DatabaseQueue")
    }
}
