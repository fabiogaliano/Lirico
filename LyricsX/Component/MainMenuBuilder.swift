import AppKit

/// Programmatic main menu and status bar menu construction.
///
/// Replaces the former `Main.storyboard` "Application" scene. Item titles,
/// tags, identifiers, key equivalents, and action selectors are preserved
/// 1:1 so existing target/action wiring (AppDelegate IBActions, shortcut
/// bindings, `validateMenuItem`, `menuNeedsUpdate` tag-202 lookup) keeps
/// working without modification.
enum MainMenuBuilder {

    /// Bundle of objects returned to `AppDelegate` so the offset view and
    /// its inner controls can be re-bound to `LyricsSession.lyricsOffset`
    /// after construction, and so `menuWillOpen` can find the constraint it
    /// adjusts when on-state menu items are present.
    struct StatusBarMenu {
        let menu: NSMenu
        let lyricsOffsetView: NSView
        let lyricsOffsetTextField: NSTextField
        let lyricsOffsetStepper: NSStepper
    }

    // MARK: - Main Menu

    /// Build the app-level menu (Application / Edit / Window).
    ///
    /// LyricsX is `LSUIElement`, so this menu is rarely visible, but Cocoa
    /// still requires it for key-equivalent dispatch (⌘Q, text-editing
    /// shortcuts, window minimize/close). Main-menu targets stay `nil` so
    /// actions route through the responder chain to NSApp / focused text view.
    static func mainMenu() -> NSMenu {
        let menu = NSMenu(title: "Main Menu")
        menu.addItem(applicationMenuItem())
        menu.addItem(editMenuItem())
        menu.addItem(windowMenuItem())
        return menu
    }

    private static func applicationMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Application")
        let quit = NSMenuItem(
            title: NSLocalizedString("Quit Application", comment: "app menu"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        submenu.addItem(quit)
        item.submenu = submenu
        return item
    }

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: NSLocalizedString("Edit", comment: "menu"))

        submenu.addItem(NSMenuItem(title: NSLocalizedString("Undo", comment: "menu"), action: Selector(("undo:")), keyEquivalent: "z"))
        submenu.addItem(NSMenuItem(title: NSLocalizedString("Redo", comment: "menu"), action: Selector(("redo:")), keyEquivalent: "Z"))
        submenu.addItem(.separator())
        submenu.addItem(NSMenuItem(title: NSLocalizedString("Cut", comment: "menu"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        submenu.addItem(NSMenuItem(title: NSLocalizedString("Copy", comment: "menu"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        submenu.addItem(NSMenuItem(title: NSLocalizedString("Paste", comment: "menu"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))

        let pastePlain = NSMenuItem(
            title: NSLocalizedString("Paste and Match Style", comment: "menu"),
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "V"
        )
        pastePlain.keyEquivalentModifierMask = [.option, .command]
        submenu.addItem(pastePlain)

        submenu.addItem(NSMenuItem(title: NSLocalizedString("Select All", comment: "menu"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        item.submenu = submenu
        return item
    }

    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: NSLocalizedString("Window", comment: "menu"))
        // Mirrors the original storyboard's `systemMenu="window"` attribute.
        NSApp.windowsMenu = submenu

        submenu.addItem(NSMenuItem(title: NSLocalizedString("Minimize", comment: "menu"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))

        submenu.addItem(NSMenuItem(title: NSLocalizedString("Hide Application", comment: "menu"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))

        let hideOthers = NSMenuItem(
            title: NSLocalizedString("Hide Others", comment: "menu"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.option, .command]
        submenu.addItem(hideOthers)

        submenu.addItem(NSMenuItem(title: NSLocalizedString("Close", comment: "menu"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        item.submenu = submenu
        return item
    }

    // MARK: - Status Bar Menu

    /// Build the menu shown from the menu-bar status item, plus the inline
    /// "Lyrics Delay Setter" view. Tags and identifiers match the original
    /// storyboard so `AppDelegate.menuNeedsUpdate(_:)` (looks up tag 202)
    /// and the SwiftUI Search/Preferences entry points continue to work.
    static func statusBarMenu(target: AppDelegate) -> StatusBarMenu {
        let menu = NSMenu()

        menu.addItem(menuBarLyricsToggleItem())
        menu.addItem(karaokeLyricsToggleItem())
        menu.addItem(showLyricsWindowItem(target: target))
        menu.addItem(.separator())

        let offset = makeLyricsOffsetView()
        menu.addItem(lyricsOffsetItem(view: offset.view))
        menu.addItem(searchLyricsItem(target: target))
        menu.addItem(lyricsSubmenuItem(target: target))
        menu.addItem(.separator())
        menu.addItem(preferencesItem(target: target))
        menu.addItem(.separator())
        menu.addItem(aboutItem(target: target))
        menu.addItem(checkUpdateItem(target: target))
        menu.addItem(.separator())
        menu.addItem(quitItem())

        return StatusBarMenu(
            menu: menu,
            lyricsOffsetView: offset.view,
            lyricsOffsetTextField: offset.textField,
            lyricsOffsetStepper: offset.stepper
        )
    }

    private static func menuBarLyricsToggleItem() -> NSMenuItem {
        let item = NSMenuItem(title: NSLocalizedString("Enable Menu Bar Lyrics", comment: "menu"), action: nil, keyEquivalent: "")
        item.tag = 100
        item.bind(
            .value,
            to: NSUserDefaultsController.shared,
            withKeyPath: "values.MenuBarLyricsEnabled",
            options: [.validatesImmediately: true]
        )
        return item
    }

    private static func karaokeLyricsToggleItem() -> NSMenuItem {
        let item = NSMenuItem(title: NSLocalizedString("Enable Karaoke Lyrics", comment: "menu"), action: nil, keyEquivalent: "")
        item.tag = 101
        item.bind(
            .value,
            to: NSUserDefaultsController.shared,
            withKeyPath: "values.DesktopLyricsEnabled",
            options: [.validatesImmediately: true]
        )
        return item
    }

    private static func showLyricsWindowItem(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString("Show Lyrics Window", comment: "menu"),
            action: #selector(AppDelegate.showLyricsHUD(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.tag = 102
        return item
    }

    private static func lyricsOffsetItem(view: NSView) -> NSMenuItem {
        let item = NSMenuItem(title: NSLocalizedString("Lyrics Delay Setter", comment: "menu"), action: nil, keyEquivalent: "")
        item.tag = 200
        item.view = view
        return item
    }

    private static func searchLyricsItem(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString("Search Lyrics...", comment: "menu"),
            action: #selector(AppDelegate.searchLyrics(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.tag = 201
        item.identifier = NSUserInterfaceItemIdentifier("MainMenu.SearchLyrics")
        applyMASReviewHidden(to: item)
        return item
    }

    private static func lyricsSubmenuItem(target: AppDelegate) -> NSMenuItem {
        let parent = NSMenuItem(title: NSLocalizedString("Lyrics", comment: "menu"), action: nil, keyEquivalent: "")
        parent.tag = 202
        parent.identifier = NSUserInterfaceItemIdentifier("MainMenu.Lyrics")

        let submenu = NSMenu(title: NSLocalizedString("Lyrics", comment: "menu"))

        let showInFinder = NSMenuItem(
            title: NSLocalizedString("Show In Finder", comment: "menu"),
            action: #selector(AppDelegate.showCurrentLyricsInFinder(_:)),
            keyEquivalent: ""
        )
        showInFinder.target = target
        submenu.addItem(showInFinder)

        let wrong = NSMenuItem(
            title: NSLocalizedString("Wrong Lyrics", comment: "menu"),
            action: #selector(AppDelegate.wrongLyrics(_:)),
            keyEquivalent: ""
        )
        wrong.target = target
        wrong.tag = 203
        wrong.identifier = NSUserInterfaceItemIdentifier("MainMenu.WrongLyrics")
        submenu.addItem(wrong)

        let disableAlbum = NSMenuItem(
            title: NSLocalizedString("Disable Lyrics for Entire Album", comment: "menu"),
            action: #selector(AppDelegate.doNotSearchLyricsForThisAlbum(_:)),
            keyEquivalent: ""
        )
        disableAlbum.target = target
        submenu.addItem(disableAlbum)

        // Tag 202 is intentionally reused: `menuNeedsUpdate` enables the
        // outer "Lyrics" item, while this inner item participates in
        // `validateMenuItem` enable/disable through its action selector.
        let writeToiTunes = NSMenuItem(
            title: NSLocalizedString("Write to iTunes", comment: "menu"),
            action: #selector(AppDelegate.writeToiTunes(_:)),
            keyEquivalent: ""
        )
        writeToiTunes.target = target
        writeToiTunes.tag = 202
        writeToiTunes.identifier = NSUserInterfaceItemIdentifier("MainMenu.WriteToiTunes")
        submenu.addItem(writeToiTunes)

        parent.submenu = submenu
        return parent
    }

    private static func preferencesItem(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString("Preferences...", comment: "menu"),
            action: #selector(AppDelegate.showPreferences(_:)),
            keyEquivalent: ","
        )
        item.target = target
        item.tag = 300
        return item
    }

    private static func aboutItem(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString("About LyricsX", comment: "menu"),
            action: #selector(AppDelegate.aboutLyricsXAction(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.tag = 400
        return item
    }

    private static func checkUpdateItem(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString("Check For Update...", comment: "menu"),
            action: #selector(AppDelegate.checkUpdateAction(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.tag = 401
        applyMASHiddenInRelease(to: item)
        applyMASReviewHidden(to: item)
        return item
    }

    private static func quitItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString("Quit LyricsX", comment: "menu"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.target = NSApp
        item.tag = 500
        return item
    }

    // MARK: - MAS-conditional visibility

    /// Hide menu items in the Mac App Store build; no-op for direct builds.
    /// Replaces the storyboard's `isHiddenInMASVersion` user-defined runtime
    /// attribute (which was driven by the `IBInspection.swift` IBInspectable).
    private static func applyMASHiddenInRelease(to item: NSMenuItem) {
        #if IS_FOR_MAS
        if isFromMacAppStore {
            item.isHidden = true
        }
        #endif
    }

    private static func applyMASReviewHidden(to item: NSMenuItem) {
        #if IS_FOR_MAS
        if defaults[.isInMASReview] != false {
            item.isHidden = true
        }
        #endif
    }

    // MARK: - Lyrics Offset View

    /// Construct the "Lyrics Offset: [field] ↕ ms" inline view shown inside
    /// the "Lyrics Delay Setter" status menu item. The leading constraint
    /// keeps its `lyricsOffsetConstraint` identifier so `menuWillOpen` can
    /// still nudge it when at least one sibling item is in `.on` state.
    private static func makeLyricsOffsetView() -> (view: NSView, textField: NSTextField, stepper: NSStepper) {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 248, height: 23))
        view.autoresizingMask = .width

        let label = NSTextField(labelWithString: NSLocalizedString("Lyrics Offset:", comment: "menu"))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byClipping
        label.font = .systemFont(ofSize: NSFont.systemFontSize)

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.controlSize = .small
        textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        textField.alignment = .center
        textField.isBezeled = true
        textField.drawsBackground = true
        textField.focusRingType = .none
        let formatter = NumberFormatter()
        formatter.minimum = -10000
        formatter.maximum = 10000
        formatter.usesGroupingSeparator = false
        formatter.allowsFloats = false
        formatter.maximumIntegerDigits = 42
        formatter.isLenient = true
        textField.formatter = formatter
        textField.stringValue = "0"

        let stepper = NSStepper()
        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.controlSize = .small
        stepper.isContinuous = true
        stepper.minValue = -10000
        stepper.maxValue = 10000
        stepper.increment = 100
        stepper.valueWraps = false

        let unit = NSTextField(labelWithString: "ms")
        unit.translatesAutoresizingMaskIntoConstraints = false
        unit.lineBreakMode = .byClipping
        unit.font = .systemFont(ofSize: NSFont.systemFontSize)

        view.addSubview(label)
        view.addSubview(textField)
        view.addSubview(stepper)
        view.addSubview(unit)

        let leading = label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 21)
        leading.identifier = "lyricsOffsetConstraint"

        NSLayoutConstraint.activate([
            leading,
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            textField.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            textField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            stepper.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 5),
            stepper.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            unit.leadingAnchor.constraint(equalTo: stepper.trailingAnchor, constant: 5),
            unit.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.trailingAnchor.constraint(equalTo: unit.trailingAnchor, constant: 21),
        ])

        return (view, textField, stepper)
    }
}
