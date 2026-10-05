import AppKit
import Combine
import GenericID
import LiricoFoundation
import ServiceManagement

/// Lirico itself launching at login, independent of the helper that waits for a player.
enum MainAppLoginItem {
    /// On, including while macOS waits for the user to allow it.
    static var isEnabled: Bool {
        [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
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

/// macOS can register a login item yet hold it back until the user allows it in
/// System Settings › General › Login Items & Extensions; nothing else reports that.
enum LoginItemApproval {
    static var isPending: Bool {
        SMAppService.mainApp.status == .requiresApproval
            || SMAppService.loginItem(identifier: lyricsXHelperIdentifier).status == .requiresApproval
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Restarts Lirico, for settings it only reads at launch.
@MainActor
enum AppRelauncher {
    static func relaunch() {
        // The new copy waits for this one to exit; running side by side, both would add
        // status items and follow the player until this one quit.
        let script = #"while /bin/kill -0 "$0" 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open "$1""#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
        do {
            try process.run()
        } catch {
            log("Failed to relaunch Lirico. reason: \(error.localizedDescription)")
            return
        }
        NSApp.terminate(nil)
    }
}

/// "Open and quit with music player": LiricoHelper, a login item, launches Lirico when a
/// supported player starts, and Lirico quits once the last one closes. Settings only
/// flips the preference; everything that follows from it happens here.
final class PlayerLifecycle {
    private let settings: PlayerSettings
    private var settingObservation: DefaultsObservation?
    private var terminationObservation: AnyCancellable?

    init(settings: PlayerSettings) {
        self.settings = settings
    }

    func start() {
        // The helper can't read Lirico's own defaults, so the setting is mirrored into the shared suite.
        groupDefaults.bind(NSBindingName(UserDefaults.DefaultsKeys.launchAndQuitWithPlayer.key), withDefaultName: .launchAndQuitWithPlayer)
        startHelperIfNeeded()
        settingObservation = defaults.observe(keys: [.launchAndQuitWithPlayer]) { [weak self] in
            self?.settingChanged()
        }
        terminationObservation = workspaceNC.publisher(for: NSWorkspace.didTerminateApplicationNotification, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [settings] notification in
                guard settings.launchAndQuitWithPlayer,
                      let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = application.bundleIdentifier else { return }
                let stillRunning = NSWorkspace.shared.runningApplications
                    .filter { $0 != application && !$0.isTerminated }
                    .compactMap(\.bundleIdentifier)
                if ScriptablePlayers.isLastToQuit(bundleID, stillRunning: stillRunning) {
                    MainActor.assumeIsolated { NSApplication.shared.terminate(nil) }
                }
            }
    }

    private func settingChanged() {
        let enabled = settings.launchAndQuitWithPlayer
        setHelperLoginItemEnabled(enabled)
        if enabled {
            startHelperIfNeeded()
        } else {
            NSRunningApplication.runningApplications(withBundleIdentifier: lyricsXHelperIdentifier)
                .forEach { $0.terminate() }
        }
    }

    private func setHelperLoginItemEnabled(_ enabled: Bool) {
        let service = SMAppService.loginItem(identifier: lyricsXHelperIdentifier)
        do {
            if enabled {
                guard service.status != .enabled, service.status != .requiresApproval else { return }
                try service.register()
            } else {
                guard service.status != .notRegistered, service.status != .notFound else { return }
                try service.unregister()
            }
        } catch {
            log("Failed to \(enabled ? "register" : "unregister") LiricoHelper login item. reason: \(error.localizedDescription)")
        }
    }

    /// The helper normally starts at login; this covers the session in which the setting was
    /// turned on or Lirico was reinstalled, so the next player launch is still noticed.
    private func startHelperIfNeeded() {
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
