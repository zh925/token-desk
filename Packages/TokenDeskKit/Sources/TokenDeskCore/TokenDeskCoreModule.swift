/// Identifies the domain module without introducing mutable global state.
public enum TokenDeskCoreModule: Sendable {
    /// The stable module name used by diagnostics and baseline tests.
    public static let name = "TokenDeskCore"
}
