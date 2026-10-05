import AppKit
import Combine
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
    private var cancelBag = Set<AnyCancellable>()

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

        // The permission check behind the header answers asynchronously, possibly while the
        // menu is open. The hop reads the status after `@Published` has stored it.
        container.session.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateNowPlayingItem() }
            .store(in: &cancelBag)

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

    // MARK: - NSMenuItemValidation

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
             #selector(wrongLyrics(_:))?:
            return container.session.currentLyrics != nil
        case #selector(showCurrentLyricsInFinder(_:))?:
            return container.session.canRevealCurrentLyricsInFinder
        case #selector(doNotSearchLyricsForThisAlbum(_:))?:
            return container.player.currentTrack?.album?.isEmpty == false
        default:
            return true
        }
    }

    // MARK: - Menubar Action

    /// No `NSApp.activate()`: the lyrics window is a non-activating panel, and the global
    /// shortcut would otherwise pull focus from the app the user is typing in.
    @IBAction func showLyricsHUD(_ sender: Any?) {
        guard let container else { return }
        if defaults[.isShowLyricsHUD] {
            container.lyricsHUD.close()
            defaults[.isShowLyricsHUD] = false
        } else {
            container.lyricsHUD.showWindow(nil)
            defaults[.isShowLyricsHUD] = true
        }
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
        // Visible but buried behind another app's windows, the shortcut should bring it forward.
        if NSApp.isActive, prefs.window?.isKeyWindow == true {
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
        container?.session.writeToiTunes()
    }

    @IBAction func searchLyrics(_ sender: Any?) {
        container?.searchLyricsWindowController.showWindow(nil)
        NSApp.activate()
    }

    @IBAction func wrongLyrics(_ sender: Any?) {
        rejectCurrentLyricsAfterConfirming(blocking: .track)
    }

    /// The shortcut skips the confirmation: it is a key the user bound on purpose,
    /// and a dialog would pull Lirico in front of whatever app they're using.
    @objc func wrongLyricsFromShortcut(_ sender: Any?) {
        container?.session.rejectCurrentLyrics(blocking: .track)
    }

    @IBAction func doNotSearchLyricsForThisAlbum(_ sender: Any?) {
        rejectCurrentLyricsAfterConfirming(blocking: .album)
    }

    private func rejectCurrentLyricsAfterConfirming(blocking scope: LyricsSession.RejectionScope) {
        guard let container else { return }
        guard defaults[.confirmBeforeBlockingLyrics] else {
            container.session.rejectCurrentLyrics(blocking: scope)
            return
        }
        let trackID = container.player.currentTrack?.id

        let alert = NSAlert()
        switch scope {
        case .track:
            alert.messageText = NSLocalizedString("Block lyrics for this song?", comment: "confirm dialog title")
            alert.informativeText = NSLocalizedString(
                "Lirico won't search lyrics for this song again until you pick some manually.",
                comment: "confirm dialog body"
            )
            alert.addButton(withTitle: NSLocalizedString("Block", comment: "confirm dialog button"))
        case .album:
            alert.messageText = NSLocalizedString("Block lyrics for this album?", comment: "confirm dialog title")
            alert.informativeText = NSLocalizedString(
                "Lirico won't search lyrics for any song on this album until you pick lyrics for one of them manually.",
                comment: "confirm dialog body"
            )
            alert.addButton(withTitle: NSLocalizedString("Block", comment: "confirm dialog button"))
        }
        alert.buttons[0].hasDestructiveAction = true
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "confirm dialog button"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = NSLocalizedString("Don't ask again", comment: "confirm dialog checkbox")

        // A menu-bar app isn't active, so without this the dialog opens behind the frontmost app.
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if alert.suppressionButton?.state == .on {
            defaults[.confirmBeforeBlockingLyrics] = false
        }
        // The song can change while the dialog is open; blocking the new one isn't what was confirmed.
        guard container.player.currentTrack?.id == trackID else { return }
        container.session.rejectCurrentLyrics(blocking: scope)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        container?.session.refreshNoTrackStatus()
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
        case .blocked(.track): NSLocalizedString("Lyrics blocked for this song", comment: "menu header status")
        case .blocked(.album): NSLocalizedString("Lyrics blocked for this album", comment: "menu header status")
        case .loaded, .noTrack, .automationDenied: nil
        }
        let subtitle = [track.artist, statusText]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
        item.subtitle = subtitle.isEmpty ? nil : subtitle
    }
}
