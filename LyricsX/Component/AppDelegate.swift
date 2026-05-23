import AppKit
import GenericID
import MusicPlayer
import Semver

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    static var shared: AppDelegate? {
        return NSApplication.shared.delegate as? AppDelegate
    }

    @IBOutlet var lyricsOffsetView: NSView!
    @IBOutlet var lyricsOffsetTextField: NSTextField!
    @IBOutlet var lyricsOffsetStepper: NSStepper!
    @IBOutlet var statusBarMenu: NSMenu!

    private let updateController = UpdateController()

    /// Constructed in `applicationDidFinishLaunching` after defaults registration
    /// so that `MusicPlayers.Selected.init()` (which reads `UserDefaults`) sees
    /// the registered values. Force-unwrapped on access; if it's nil, AppKit
    /// invoked a menu action before `applicationDidFinishLaunching` finished,
    /// which is a bug we'd want to learn about loudly.
    private var container: AppContainer!

    var firstLaunchForShouldHanlderReopen: Bool = true

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        UserDefaultsRegistration.register()

        let container = AppContainer()
        self.container = container
        _ = LyricsSelector.shared
        container.start(statusBarMenu: statusBarMenu)
        statusBarMenu.delegate = self

        LyricsOffsetMenuBindings.install(
            stepper: lyricsOffsetStepper,
            textField: lyricsOffsetTextField,
            session: container.session
        )

        ShortcutBindings.install(actionTarget: self)

        HelperLifecycle.terminateRunningHelper()

        let sharedKeys: [UserDefaults.DefaultsKeys] = [
            .launchAndQuitWithPlayer,
            .preferredPlayerIndex,
        ]
        for sharedKey in sharedKeys {
            groupDefaults.bind(NSBindingName(sharedKey.key), withDefaultName: sharedKey)
        }

        updateController.startIfEnabled()

        if defaults[.isShowLyricsHUD] {
            container.lyricsHUD.showWindow(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if firstLaunchForShouldHanlderReopen {
            firstLaunchForShouldHanlderReopen = false
            return false
        }
        container?.preferencesWindowController.showWindow(nil)
        return true
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        container?.session.prepareForTermination()
        HelperLifecycle.openHelperOnQuitIfNeeded()
    }

    // MARK: - NSMenuDelegate

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let container else { return false }
        switch menuItem.action {
        case #selector(writeToiTunes(_:))?:
            return container.player.name == .appleMusic && container.session.currentLyrics != nil
        case #selector(searchLyrics(_:))?:
            return container.player.currentTrack != nil
        default:
            return true
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: 202)?.isEnabled = container?.session.currentLyrics != nil
    }

    // MARK: - Menubar Action

    @IBAction func showLyricsHUD(_ sender: Any?) {
        guard let container else { return }
        if defaults[.isShowLyricsHUD] {
            container.lyricsHUD.close()
            defaults[.isShowLyricsHUD] = false
        } else {
            container.lyricsHUD.showWindow(nil)
            defaults[.isShowLyricsHUD] = true
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    @IBAction func aboutLyricsXAction(_ sender: Any) {
        if #available(OSX 10.13, *) {
            let channel = "GitHub"
            let versionString = "\(channel) Version \(Bundle.main.semanticVersion ?? "Unknown")"
            NSApp.orderFrontStandardAboutPanel(options: [.applicationVersion: versionString])
        } else {
            NSApp.orderFrontStandardAboutPanel(sender)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @IBAction func showPreferences(_ sender: Any?) {
        container?.preferencesWindowController.showWindow(nil)
    }

    @objc func togglePreferences(_ sender: Any?) {
        guard let prefs = container?.preferencesWindowController else { return }
        if prefs.window?.isVisible ?? false {
            prefs.close()
        } else {
            prefs.showWindow(nil)
        }
    }

    @IBAction func checkUpdateAction(_ sender: Any) {
        updateController.checkForUpdates(sender)
    }

    @IBAction func increaseOffset(_ sender: Any?) {
        container?.session.lyricsOffset += 100
    }

    @IBAction func decreaseOffset(_ sender: Any?) {
        container?.session.lyricsOffset -= 100
    }

    @IBAction func showCurrentLyricsInFinder(_ sender: Any?) {
        container?.session.revealCurrentLyricsInFinder()
    }

    @IBAction func writeToiTunes(_ sender: Any?) {
        container?.session.writeToiTunes(overwrite: true)
    }

    @IBAction func searchLyrics(_ sender: Any?) {
        container?.searchLyricsWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @IBAction func wrongLyrics(_ sender: Any?) {
        guard let container, let track = container.player.currentTrack else {
            return
        }
        SearchBlocklist.block(track: track)
        container.session.clear(deleteOnDisk: true)
    }

    @IBAction func doNotSearchLyricsForThisAlbum(_ sender: Any?) {
        guard let container,
              let track = container.player.currentTrack,
              let album = track.album else {
            return
        }
        SearchBlocklist.block(album: album)
        container.session.clear(deleteOnDisk: true)
    }

    func menuWillOpen(_ menu: NSMenu) {
        if #available(macOS 11, *) {
            let menuHasOnState = statusBarMenu.items.filter { menuItem in
                return menuItem.state == .on
            }.count > 0

            let lyricsOffsetConstraint = lyricsOffsetView.constraints.first(where: { $0.identifier == "lyricsOffsetConstraint" })

            lyricsOffsetConstraint?.constant = 14
            if menuHasOnState {
                lyricsOffsetConstraint?.constant += 10
            }
        }
    }
}

