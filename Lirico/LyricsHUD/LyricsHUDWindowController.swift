import AppKit

/// Programmatic owner of the lyrics HUD floating panel.
///
/// Replaces the former storyboard-backed `StoryboardWindowController`:
/// constructs the NSPanel and its content `LyricsHUDViewController` here
/// rather than relying on `NSStoryboard.main.instantiateController`. The
/// initializer accepts the same dependencies the view controller needs so
/// `AppContainer` can hand them off without a follow-up `configure(...)`.
final class LyricsHUDWindowController: NSWindowController, NSWindowDelegate {

    private static let windowFrame = NSWindow.FrameAutosaveName("LyricsHUD")

    init(
        player: PlayerHandle,
        session: LyricsSession,
        chineseConverter: ChineseConverterProvider,
        explicitResolver: ExplicitLyricsResolving
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
}
