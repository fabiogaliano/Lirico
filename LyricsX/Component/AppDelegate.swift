import AppKit
import GenericID
import MASShortcut
import MusicPlayer
import Sparkle
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

    private lazy var updateController = SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: self)

    // TODO: Flip to true once SUPublicEDKey is generated and pasted into Info.plist.
    private let isSparkleEnabled = false

    /// Constructed in `applicationDidFinishLaunching` after defaults registration
    /// so that `MusicPlayers.Selected.init()` (which reads `UserDefaults`) sees
    /// the registered values. Force-unwrapped on access; if it's nil, AppKit
    /// invoked a menu action before `applicationDidFinishLaunching` finished,
    /// which is a bug we'd want to learn about loudly.
    private var container: AppContainer!

    var firstLaunchForShouldHanlderReopen: Bool = true

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        registerUserDefaults()

        let container = AppContainer()
        self.container = container
        _ = LyricsSelector.shared
        container.start(statusBarMenu: statusBarMenu)
        statusBarMenu.delegate = self

        let session = container.session
        lyricsOffsetStepper.bind(
            .value,
            to: session,
            withKeyPath: #keyPath(LyricsSession.lyricsOffset),
            options: [.continuouslyUpdatesValue: true]
        )
        lyricsOffsetTextField.bind(
            .value,
            to: session,
            withKeyPath: #keyPath(LyricsSession.lyricsOffset),
            options: [.continuouslyUpdatesValue: true]
        )

        setupShortcuts()

        NSRunningApplication.runningApplications(withBundleIdentifier: lyricsXHelperIdentifier).forEach { $0.terminate() }

        let sharedKeys: [UserDefaults.DefaultsKeys] = [
            .launchAndQuitWithPlayer,
            .preferredPlayerIndex,
        ]
        for sharedKey in sharedKeys {
            groupDefaults.bind(NSBindingName(sharedKey.key), withDefaultName: sharedKey)
        }

        if isSparkleEnabled {
            updateController.updater.checkForUpdatesInBackground()
        }

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
        if defaults[.launchAndQuitWithPlayer] {
            let url = Bundle.main.bundleURL
                .appendingPathComponent("Contents/Library/LoginItems/LyricsXHelper.app")
            groupDefaults[.launchHelperTime] = Date()

            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { application, error in
                if let error = error {
                    log("launch LyricsX Helper failed. reason: \(error)")
                } else {
                    log("launch LyricsX Helper succeed.")
                }
            }
        }
    }

    private func setupShortcuts() {
        let binder = MASShortcutBinder.shared()!
        binder.bindBoolShortcut(.shortcutToggleMenuBarLyrics, target: .menuBarLyricsEnabled)
        binder.bindBoolShortcut(.shortcutToggleKaraokeLyrics, target: .desktopLyricsEnabled)
        binder.bindShortcut(.shortcutShowLyricsWindow, to: #selector(showLyricsHUD))
        binder.bindShortcut(.shortcutOffsetIncrease, to: #selector(increaseOffset))
        binder.bindShortcut(.shortcutOffsetDecrease, to: #selector(decreaseOffset))
        binder.bindShortcut(.shortcutWriteToiTunes, to: #selector(writeToiTunes))
        binder.bindShortcut(.shortcutWrongLyrics, to: #selector(wrongLyrics))
        binder.bindShortcut(.shortcutSearchLyrics, to: #selector(searchLyrics))
        binder.bindShortcut(.shortcutTogglePreferences, to: #selector(togglePreferences))
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
        guard isSparkleEnabled else { return }
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

    func registerUserDefaults() {
        let currentLang = NSLocale.preferredLanguages.first!
        let isZh = currentLang.hasPrefix("zh") || currentLang.hasPrefix("yue")
        let isHant = isZh && (currentLang.contains("-Hant") || currentLang.contains("-HK"))

        let defaultsUrl = Bundle.main.url(forResource: "UserDefaults", withExtension: "plist")!
        if let dict = NSDictionary(contentsOf: defaultsUrl) as? [String: Any] {
            defaults.register(defaults: dict)
        }
        defaults.register(defaults: [
            .desktopLyricsColor: NSColor.white,
            .desktopLyricsProgressColor: NSColor.controlAccentColor,
            .desktopLyricsShadowColor: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.55),
            .desktopLyricsBackgroundColor: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.85),
            .lyricsWindowTextColor: #colorLiteral(red: 0.6, green: 0.6, blue: 0.6, alpha: 1),
            .lyricsWindowHighlightColor: NSColor.controlAccentColor,
            .preferBilingualLyrics: isZh,
            .chineseConversionIndex: isHant ? 2 : 0,
            .desktopLyricsXPositionFactor: 0.5,
            .desktopLyricsYPositionFactor: 0.9,
        ])
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

extension AppDelegate: SPUStandardUserDriverDelegate {
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        return true
    }
}

extension MASShortcutBinder {
    func bindShortcut<T>(_ defaultsKay: UserDefaults.DefaultsKey<T>, to action: @escaping () -> Void) {
        bindShortcut(withDefaultsKey: defaultsKay.key, toAction: action)
    }

    func bindBoolShortcut<T>(_ defaultsKay: UserDefaults.DefaultsKey<T>, target: UserDefaults.DefaultsKey<Bool>) {
        bindShortcut(withDefaultsKey: defaultsKay.key) {
            defaults[target] = !defaults[target]
        }
    }

    func bindShortcut<T>(_ defaultsKay: UserDefaults.DefaultsKey<T>, to action: Selector) {
        bindShortcut(defaultsKay) {
            let target = NSApplication.shared.target(forAction: action) as AnyObject?
            _ = target?.perform(action, with: self)
        }
    }
}
