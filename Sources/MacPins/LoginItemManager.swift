import ServiceManagement

enum LoginItemState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

enum LoginItemManager {
    static var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            // Service Management reports this before a main-app login item has
            // ever been registered. It is still available to turn on.
            return .disabled
        @unknown default:
            return .unavailable
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled && service.status != .requiresApproval {
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }
}
