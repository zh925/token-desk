import Observation

/// Top-level destinations in the Token Desk application shell.
public enum AppRoute: String, CaseIterable, Sendable {
    case overview
    case plans
    case tokens
    case settings

    /// Localized title displayed by the header and page shell.
    public var title: String {
        switch self {
        case .overview: "总览"
        case .plans: "套餐"
        case .tokens: "Token"
        case .settings: "设置"
        }
    }

    /// Direct keyboard shortcut for a primary navigation destination.
    public var keyboardShortcut: Character? {
        switch self {
        case .overview: "1"
        case .plans: "2"
        case .tokens: "3"
        case .settings: nil
        }
    }

    /// Stable accessibility identifier for navigation automation.
    public var accessibilityIdentifier: String {
        "route-\(rawValue)"
    }

    /// Routes available in the central navigation group.
    public static let primaryNavigation: [AppRoute] = [.overview, .plans, .tokens]
}

/// Main-actor navigation state for synchronous, testable page switching.
@MainActor
@Observable
public final class AppRouter {
    /// The currently visible destination.
    public private(set) var route: AppRoute

    /// Creates a router at the supplied destination.
    public init(route: AppRoute = .overview) {
        self.route = route
    }

    /// Selects a destination synchronously.
    public func select(_ route: AppRoute) {
        self.route = route
    }

    /// Selects a primary destination for the unmodified `1`, `2`, or `3` key.
    @discardableResult
    public func selectShortcut(_ character: Character) -> Bool {
        guard
            let route = AppRoute.primaryNavigation.first(where: {
                $0.keyboardShortcut == character
            })
        else {
            return false
        }

        select(route)
        return true
    }
}
