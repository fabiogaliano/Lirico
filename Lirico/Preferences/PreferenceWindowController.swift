import AppKit
import SwiftUI

class PreferenceWindowController: NSWindowController {
    private static let contentSize = NSSize(width: 620, height: 600)

    convenience init() {
        // Toolbar-style tabs are what macOS apps use for Settings; a SwiftUI TabView in a plain
        // window renders as a segmented control floating over the content instead.
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true
        for pane in PreferencePane.allCases {
            let host = NSHostingController(rootView: pane.view)
            host.sizingOptions = []
            host.preferredContentSize = Self.contentSize
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.setContentSize(Self.contentSize)
        window.center()
        self.init(window: window)
    }

    static func create() -> PreferenceWindowController {
        return PreferenceWindowController()
    }

    override func showWindow(_ sender: Any?) {
        // Activate first: a menu-bar app isn't active when its menu is used, and a window shown
        // before activation opens behind the frontmost app, needing a second click to surface.
        NSApp.activate()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }
}

private enum PreferencePane: CaseIterable {
    case general, lyrics, appearance, sources, filter, shortcuts

    var title: String {
        switch self {
        case .general: NSLocalizedString("General", comment: "settings tab")
        case .lyrics: NSLocalizedString("Lyrics", comment: "settings tab")
        case .appearance: NSLocalizedString("Appearance", comment: "settings tab")
        case .sources: NSLocalizedString("Sources", comment: "settings tab")
        case .filter: NSLocalizedString("Filter", comment: "settings tab")
        case .shortcuts: NSLocalizedString("Shortcuts", comment: "settings tab")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .lyrics: "text.quote"
        case .appearance: "paintbrush"
        case .sources: "globe"
        case .filter: "line.3.horizontal.decrease.circle"
        case .shortcuts: "keyboard"
        }
    }

    @MainActor
    var view: AnyView {
        switch self {
        case .general: AnyView(GeneralPreferencesView())
        case .lyrics: AnyView(LyricsPreferencesView())
        case .appearance: AnyView(DisplayPreferencesView())
        case .sources: AnyView(SourcePreferencesView())
        case .filter: AnyView(FilterPreferencesView())
        case .shortcuts: AnyView(ShortcutPreferencesView())
        }
    }
}
