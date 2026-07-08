import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+). Registers the app bundle so
/// it starts automatically and is always ready in the menu bar.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            Diag.log("LOGINITEM: set launch-at-login = \(enabled) (status: \(SMAppService.mainApp.status.rawValue))")
            return true
        } catch {
            Diag.log("LOGINITEM: failed to set launch-at-login: \(error)")
            return false
        }
    }
}
