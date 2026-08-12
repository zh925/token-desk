import SwiftUI

private struct TokenDeskReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Test-only override that exercises the same no-animation branch as Reduce Motion.
    public var tokenDeskReduceMotionOverride: Bool {
        get { self[TokenDeskReduceMotionOverrideKey.self] }
        set { self[TokenDeskReduceMotionOverrideKey.self] = newValue }
    }
}
