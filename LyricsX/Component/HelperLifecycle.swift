import AppKit

enum HelperLifecycle {
    static func terminateRunningHelper() {
        NSRunningApplication.runningApplications(withBundleIdentifier: lyricsXHelperIdentifier)
            .forEach { $0.terminate() }
    }

    static func openHelperOnQuitIfNeeded() {
        guard defaults[.launchAndQuitWithPlayer] else { return }
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/LyricsXHelper.app")
        groupDefaults[.launchHelperTime] = Date()
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error = error {
                log("launch LyricsX Helper failed. reason: \(error)")
            } else {
                log("launch LyricsX Helper succeed.")
            }
        }
    }
}
