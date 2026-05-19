import AppKit
import UIFoundation

class PreferenceWindowController: NSWindowController, StoryboardWindowController {
    static var storyboard: NSStoryboard { .init(name: "Preferences", bundle: .main) }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}
