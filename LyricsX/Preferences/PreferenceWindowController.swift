import AppKit
import SwiftUI

class PreferenceWindowController: NSWindowController {
    convenience init() {
        let hostingController = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "LyricsX Preferences"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 600, height: 450))
        window.center()
        self.init(window: window)
    }

    static func create() -> PreferenceWindowController {
        return PreferenceWindowController()
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate()
    }
}
