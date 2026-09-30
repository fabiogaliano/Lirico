import AppKit
import GenericID
import MusicPlayer

@MainActor
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

    /// Constructed in `applicationDidFinishLaunching` after defaults registration
    /// so that `MusicPlayers.Selected.init()` (which reads `UserDefaults`) sees
    /// the registered values.
    private var container: AppContainer!

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

        for control in [built.lyricsOffsetStepper, built.lyricsOffsetTextField] as [NSControl] {
            control.bind(
                .value,
                to: container.session,
                withKeyPath: #keyPath(LyricsSession.lyricsOffset),
                options: [.continuouslyUpdatesValue: true]
            )
        }

        ShortcutBindings.install(actionTarget: self)

        if defaults[.isShowLyricsHUD] {
            container.lyricsHUD.showWindow(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        container?.preferencesWindowController.showWindow(nil)
        return true
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        container?.session.prepareForTermination()
    }

    // MARK: - NSMenuDelegate

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let container else { return false }
        switch menuItem.action {
        case #selector(writeToiTunes(_:))?:
            return container.session.canWriteToAppleMusic
        case #selector(searchLyrics(_:))?:
            return container.player.currentTrack != nil
        case #selector(showLyricsHUD(_:))?:
            // The item toggles the window, so show which way it will go like the toggles above it.
            menuItem.state = defaults[.isShowLyricsHUD] ? .on : .off
            return true
        case #selector(showLyricsSync(_:))?,
             #selector(showCurrentLyricsInFinder(_:))?,
             #selector(wrongLyrics(_:))?:
            return container.session.currentLyrics != nil
        case #selector(doNotSearchLyricsForThisAlbum(_:))?:
            return container.player.currentTrack?.album?.isEmpty == false
        default:
            return true
        }
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

    @IBAction func showLyricsSync(_ sender: Any?) {
        guard let container else { return }
        container.lyricsSync.showWindow(nil)
        NSApp.activate()
    }

    @IBAction func aboutLiricoAction(_ sender: Any) {
        NSApp.activate()
        container?.aboutWindowController.showWindow(nil)
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
        container?.session.rejectCurrentLyrics(blocking: .track)
    }

    @IBAction func doNotSearchLyricsForThisAlbum(_ sender: Any?) {
        container?.session.rejectCurrentLyrics(blocking: .album)
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateNowPlayingItem()
        let menuHasOnState = statusBarMenu.items.contains(where: { $0.state == .on })
        let lyricsOffsetConstraint = lyricsOffsetView.constraints.first(where: { $0.identifier == "lyricsOffsetConstraint" })
        lyricsOffsetConstraint?.constant = menuHasOnState ? 24 : 14
    }

    @objc private func openAutomationSettings(_ sender: Any?) {
        AutomationPermission.openSystemSettings()
    }

    private func updateNowPlayingItem() {
        guard let container,
              let item = statusBarMenu.items.first(where: { $0.identifier == MainMenuBuilder.nowPlayingIdentifier }) else { return }
        item.action = nil
        guard let track = container.player.currentTrack else {
            container.session.refreshNoTrackStatus()
            if case let .automationDenied(playerName) = container.session.status {
                item.title = String(
                    format: NSLocalizedString("Lirico Can't See What %@ Is Playing", comment: "menu header when Automation access is denied"),
                    playerName
                )
                item.subtitle = NSLocalizedString("Allow access in Privacy & Security → Automation…", comment: "menu header hint")
                item.action = #selector(openAutomationSettings(_:))
                item.target = self
            } else {
                item.title = NSLocalizedString("Nothing Playing", comment: "menu header when no track is playing")
                item.subtitle = nil
            }
            return
        }
        item.title = track.title ?? NSLocalizedString("Unknown Title", comment: "menu header")
        let statusText: String? = switch container.session.status {
        case .searching: NSLocalizedString("Searching for lyrics…", comment: "menu header status")
        case .notFound: NSLocalizedString("No lyrics found", comment: "menu header status")
        case .blocked: NSLocalizedString("Lyrics disabled for this song", comment: "menu header status")
        case .loaded, .noTrack, .automationDenied: nil
        }
        let subtitle = [track.artist, statusText]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
        item.subtitle = subtitle.isEmpty ? nil : subtitle
    }
}
