import AppKit
import ServiceManagement

/// "Launch at Login": the app registered as a login item through SMAppService (the documented interface since macOS 13).
/// The system keeps the state, so it is the same thing as the switch under System Settings › General › Login Items; nothing is stored in the preferences.
enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Registers or unregisters. Returns the message for the user when it could not be done, or when the system wants the user to allow it first.
    static func set(_ on: Bool) -> String? {
        let service = SMAppService.mainApp
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            Log.write("Login item: \(on ? "register" : "unregister") failed \(error.localizedDescription)")
            return on ? String(localized: "Couldn't add Hoopa to the login items: \(error.localizedDescription)")
                      : String(localized: "Couldn't remove Hoopa from the login items: \(error.localizedDescription)")
        }
        let status = service.status
        Log.write("Login item: \(on ? "registered" : "unregistered"), status=\(status.rawValue)")
        // The user switched it off under Login Items earlier: the registration is kept but waits for them to allow it there.
        if on, status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return String(localized: "Allow Hoopa under System Settings › General › Login Items")
        }
        return nil
    }
}
