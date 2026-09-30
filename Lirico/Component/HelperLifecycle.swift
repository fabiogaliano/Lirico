import AppKit
import ServiceManagement

/// Lirico itself launching at login, independent of the helper that waits for a player.
enum MainAppLoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log("Failed to \(enabled ? "register" : "unregister") Lirico as a login item. reason: \(error.localizedDescription)")
        }
    }
}

enum HelperLifecycle {
    static func setLoginItemEnabled(_ enabled: Bool) -> Result<Void, Error> {
        let service = SMAppService.loginItem(identifier: lyricsXHelperIdentifier)
        do {
            if enabled {
                guard service.status != .enabled, service.status != .requiresApproval else {
                    return .success(())
                }
                try service.register()
            } else {
                guard service.status != .notRegistered, service.status != .notFound else {
                    return .success(())
                }
                try service.unregister()
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    static func terminateRunningHelper() {
        NSRunningApplication.runningApplications(withBundleIdentifier: lyricsXHelperIdentifier)
            .forEach { $0.terminate() }
    }

    /// The helper normally starts at login; this covers the session in which the setting was
    /// turned on or Lirico was reinstalled, so the next player launch is still noticed.
    static func startHelperIfNeeded(settings: PlayerSettings = PlayerSettings()) {
        guard settings.launchAndQuitWithPlayer,
              NSRunningApplication.runningApplications(withBundleIdentifier: lyricsXHelperIdentifier).isEmpty else { return }
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/LiricoHelper.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                log("launch Lirico Helper failed. reason: \(error)")
            }
        }
    }
}
