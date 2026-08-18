import ServiceManagement

@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Quick Reminders: launch at login toggle failed — \(error.localizedDescription)")
            }
        }
    }
}
