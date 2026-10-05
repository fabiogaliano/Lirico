import AppKit

/// Programmatic owner of the lyrics HUD floating panel.
///
/// Replaces the former storyboard-backed `StoryboardWindowController`:
/// constructs the NSPanel and its content `LyricsHUDViewController` here
/// rather than relying on `NSStoryboard.main.instantiateController`. The
/// initializer accepts the same dependencies the view controller needs so
/// `AppContainer` can hand them off without a follow-up `configure(...)`.
final class LyricsHUDWindowController: NSWindowController {

    private static let windowFrame = NSWindow.FrameAutosaveName("LyricsHUD")

    init(
        player: PlayerHandle,
        session: LyricsSession,
        chineseConverter: ChineseConverterProvider,
        explicitResolver: ExplicitLyricsResolver
    ) {
        // Matches the storyboard's `NSPanel` config: HUD style, utility, non-
        // activating, full-size content view, hidden title, persistent frame.
        let styleMask: NSWindow.StyleMask = [
            .titled, .closable, .miniaturizable, .resizable,
            .utilityWindow, .nonactivatingPanel, .hudWindow, .fullSizeContentView,
        ]
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
            styleMask: styleMask,
            backing: .buffered,
            defer: true
        )
        panel.title = NSLocalizedString("Lyrics Window", comment: "HUD title")
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .default
        // Set here as well as by the lock toggle, which only changes the level when clicked.
        panel.level = defaults[.lyricsWindowKeepsOnTop] ? .floating : .normal
        panel.setFrameAutosaveName(LyricsHUDWindowController.windowFrame)

        let viewController = LyricsHUDViewController(
            player: player,
            session: session,
            chineseConverter: chineseConverter,
            explicitResolver: explicitResolver
        )
        panel.contentViewController = viewController

        super.init(window: panel)
        panel.delegate = viewController

        // The lock-state titlebar accessory was a separate storyboard scene;
        // construct it programmatically and attach so the "always on top"
        // toggle keeps working from the HUD's title bar.
        let accessory = LyricsHUDAccessoryViewController()
        accessory.layoutAttribute = .right
        panel.addTitlebarAccessoryViewController(accessory)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Place the panel before showing it, then resume following the current line.
    ///
    /// The panel is built with a `(0,0)` content rect, which lands bottom-left in
    /// macOS's flipped screen coordinates — often under the Dock or off-screen on a
    /// multi-monitor setup, which is why the Lyrics Window menu item looked like it did
    /// nothing. Hence the saved frame, or the center of the screen.
    override func showWindow(_ sender: Any?) {
        if let window, !window.isVisible {
            window.restoreFrame(named: Self.windowFrame)
        }
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        // Deferred so the view is laid out before we scroll the current line into
        // the band; `viewWillAppear` doesn't fire dependably for a reused window.
        DispatchQueue.main.async { [weak self] in
            (self?.contentViewController as? LyricsHUDViewController)?.resumeFollowing()
        }
    }
}
