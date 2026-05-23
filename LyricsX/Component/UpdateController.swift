import AppKit
import Sparkle

final class UpdateController: NSObject, SPUStandardUserDriverDelegate {
    // TODO: Flip to true once SUPublicEDKey is generated and pasted into Info.plist.
    private let isEnabled = false

    private lazy var updater = SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: self)

    func startIfEnabled() {
        guard isEnabled else { return }
        updater.updater.checkForUpdatesInBackground()
    }

    func checkForUpdates(_ sender: Any?) {
        guard isEnabled else { return }
        updater.checkForUpdates(sender)
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        return true
    }
}
