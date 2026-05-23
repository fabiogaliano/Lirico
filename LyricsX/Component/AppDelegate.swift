import AppKit
import GenericID
import MusicPlayer
import Semver

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    static var shared: AppDelegate? {
        return NSApplication.shared.delegate as? AppDelegate
    }

    /// Status-bar menu and offset-view references, populated programmatically
    /// in `applicationDidFinishLaunching` after defaults registration. Force-
    /// unwrapped on access; if nil, AppKit dispatched a menu action before
    /// launch finished — a bug we want to fail loudly on.
    private var statusBarMenu: NSMenu!
    private var lyricsOffsetView: NSView!

    private let updateController = UpdateController()

    /// Constructed in `applicationDidFinishLaunching` after defaults registration
    /// so that `MusicPlayers.Selected.init()` (which reads `UserDefaults`) sees
    /// the registered values.
    private var container: AppContainer!

    var firstLaunchForShouldHanlderReopen: Bool = true

    /// Install the app's main menu before the run loop processes key events.
    /// Without this, Cocoa has no menu to dispatch key equivalents to and
    /// editing shortcuts (⌘C/V/Z) silently no-op in any embedded text view.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.mainMenu()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        UserDefaultsRegistration.register()

        let built = MainMenuBuilder.statusBarMenu(target: self)
        self.statusBarMenu = built.menu
        self.lyricsOffsetView = built.lyricsOffsetView

        let container = AppContainer()
        self.container = container
        container.start(statusBarMenu: built.menu)
        built.menu.delegate = self

        LyricsOffsetMenuBindings.install(
            stepper: built.lyricsOffsetStepper,
            textField: built.lyricsOffsetTextField,
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
        HelperLifecycle.openHelperOnQuitIfNeeded(settings: container?.playerSettings ?? PlayerSettings())
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

        NSApp.activate()
    }

    @IBAction func aboutLyricsXAction(_ sender: Any) {
        let channel = "GitHub"
        let versionString = "\(channel) Version \(Bundle.main.semanticVersion ?? "Unknown")"
        NSApp.orderFrontStandardAboutPanel(options: [.applicationVersion: versionString])
        NSApp.activate()
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
        NSApp.activate()
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
        let menuHasOnState = statusBarMenu.items.contains(where: { $0.state == .on })
        let lyricsOffsetConstraint = lyricsOffsetView.constraints.first(where: { $0.identifier == "lyricsOffsetConstraint" })
        lyricsOffsetConstraint?.constant = menuHasOnState ? 24 : 14
    }
}

