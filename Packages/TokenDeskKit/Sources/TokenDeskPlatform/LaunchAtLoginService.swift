import ServiceManagement
import TokenDeskCore

/// Registers the main app with Apple's supported login-item API.
@MainActor
public final class LaunchAtLoginService: LaunchAtLoginServicing {
    private let service: SMAppService

    /// Creates a service for the containing main application.
    public init(service: SMAppService = .mainApp) {
        self.service = service
    }

    /// Current registration status, including approval required in System Settings.
    public var status: LaunchAtLoginStatus {
        Self.status(from: service.status)
    }

    /// Applies the user's explicit login-startup choice.
    public func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }

    static func status(from status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }
}
