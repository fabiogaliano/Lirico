import AppKit
import Combine
import GenericID
import LiricoFoundation
import MusicPlayer

/// Programmatic owner of the "Sync by Ear" floating panel.
///
/// Mirrors `LyricsHUDWindowController`: builds an `NSPanel` and injects the same
/// dependencies the content controller needs. The panel floats above normal
/// windows so the user can browse and tap while the song keeps playing.
final class LyricsSyncWindowController: NSWindowController {

    private static let windowFrame = NSWindow.FrameAutosaveName("LyricsSync")

    init(
        player: PlayerHandle,
        session: LyricsSession,
        chineseConverter: ChineseConverterProvider,
        explicitResolver: ExplicitLyricsResolving
    ) {
        let styleMask: NSWindow.StyleMask = [
            .titled, .closable, .resizable,
            .utilityWindow, .nonactivatingPanel, .hudWindow, .fullSizeContentView,
        ]
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
            styleMask: styleMask,
            backing: .buffered,
            defer: true
        )
        panel.title = NSLocalizedString("Sync Lyrics", comment: "sync panel title")
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .default
        panel.level = .floating
        panel.setFrameAutosaveName(LyricsSyncWindowController.windowFrame)

        let viewController = LyricsSyncViewController(
            player: player,
            session: session,
            chineseConverter: chineseConverter,
            explicitResolver: explicitResolver
        )
        panel.contentViewController = viewController

        super.init(window: panel)
        panel.delegate = viewController
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Center the panel on every open. The autosaved frame still restores the
    /// user's chosen *size*, but the origin is always re-centered so the panel
    /// never reappears in a screen corner (the default `(0,0)` content rect lands
    /// bottom-left in macOS's flipped screen coordinates). `visibleFrame` excludes
    /// the menu bar and Dock, so midX/midY give a true horizontal+vertical center.
    override func showWindow(_ sender: Any?) {
        if let window, let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            ))
        }
        super.showWindow(sender)
        // Always reopen following the current line, even if the user had scrolled
        // away before closing. The controller is a reused singleton, so its
        // `isFollowing` survives across opens; resume explicitly here rather than
        // relying on `viewWillAppear`, which doesn't fire dependably for a reused
        // window. Deferred so the view is laid out before we scroll.
        DispatchQueue.main.async { [weak self] in
            (self?.contentViewController as? LyricsSyncViewController)?.resumeFollowing()
        }
    }
}

/// Content controller for the sync panel.
///
/// Two interaction modes:
/// - **Following** (default): the strip auto-scrolls to keep the synced line in
///   the NOW band as the music plays.
/// - **Browsing**: any user scroll switches to this; the strip stays where the
///   user left it so they can hunt for the line they hear, while playback keeps
///   its current sync. A "Now" pill returns to following.
///
/// Only a **tap** commits a change: it aligns the tapped line to the present
/// playback time via `LyricsOffsetSolver`, written through
/// `LyricsSession.lyricsOffset` (which re-ticks the clock and live-updates every
/// other surface). Scrolling never touches the offset.
final class LyricsSyncViewController: NSViewController, NSWindowDelegate, ScrollLyricsViewDelegate {

    private let player: PlayerHandle
    private let session: LyricsSession
    private let chineseConverter: ChineseConverterProvider
    private let explicitResolver: ExplicitLyricsResolving

    private let scrollLyricsView = ScrollLyricsView(frame: .zero)
    private let nowBand = LyricsNowBandView()
    private let noLyricsLabel = NSTextField(labelWithString: "")
    private let offsetLabel = NSTextField(labelWithString: "")
    private let playPauseButton = NSButton()
    private let seekBackButton = NSButton()
    private let seekForwardButton = NSButton()
    private let decreaseButton = NSButton()
    private let increaseButton = NSButton()
    private let resetButton = NSButton()
    private let doneButton = NSButton()
    private let recenterButton = NSButton()

    /// `true` while the music drives the scroll position; `false` once the user
    /// scrolls to browse. Toggling visibility of the "Now" pill follows it.
    private var isFollowing = true {
        didSet { recenterButton.isHidden = isFollowing }
    }

    private var cancelBag = Set<AnyCancellable>()
    private var offsetObservation: NSKeyValueObservation?

    /// Drives the intra-line karaoke fill while playing. Line-index changes alone
    /// are too coarse for word-level progress, so this ticks ~30Hz and repaints
    /// the current line's sung prefix; it's stopped when paused or hidden.
    private lazy var follower = LyricsLineFollower(
        scrollView: scrollLyricsView, nowBand: nowBand, session: session, hidesBandOnKaraokeLines: true
    )

    init(
        player: PlayerHandle,
        session: LyricsSession,
        chineseConverter: ChineseConverterProvider,
        explicitResolver: ExplicitLyricsResolving
    ) {
        self.player = player
        self.session = session
        self.chineseConverter = chineseConverter
        self.explicitResolver = explicitResolver
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 520))
        self.view = root

        for subview in [scrollLyricsView, noLyricsLabel, nowBand] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }

        noLyricsLabel.alignment = .center
        noLyricsLabel.font = .systemFont(ofSize: 15)
        noLyricsLabel.textColor = .white
        noLyricsLabel.maximumNumberOfLines = 0
        noLyricsLabel.stringValue = NSLocalizedString("No Lyrics", comment: "sync empty state")

        offsetLabel.alignment = .center
        offsetLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        offsetLabel.toolTip = NSLocalizedString("Current lyrics offset", comment: "sync readout")

        configureImageButton(seekBackButton, symbol: "gobackward.5", label: NSLocalizedString("Back 5 Seconds", comment: "sync"), action: #selector(seekBackward))
        configureImageButton(seekForwardButton, symbol: "goforward.5", label: NSLocalizedString("Forward 5 Seconds", comment: "sync"), action: #selector(seekForward))
        configureImageButton(playPauseButton, symbol: "play.fill", label: NSLocalizedString("Play", comment: "sync"), action: #selector(togglePlayPause))
        playPauseButton.toolTip = NSLocalizedString("Play / Pause", comment: "sync")
        configureTextButton(decreaseButton, title: "−100", action: #selector(decreaseOffset))
        configureTextButton(increaseButton, title: "+100", action: #selector(increaseOffset))
        configureTextButton(resetButton, title: NSLocalizedString("Reset", comment: "sync"), action: #selector(resetOffset))
        configureTextButton(doneButton, title: NSLocalizedString("Done", comment: "sync"), action: #selector(done))
        doneButton.keyEquivalent = "\r"

        // The "Now" pill floats over the lyrics and only shows while browsing;
        // it returns to following without changing the offset.
        configureTextButton(recenterButton, title: NSLocalizedString("Resume", comment: "sync"), action: #selector(recenter))
        recenterButton.image = NSImage(systemSymbolName: "arrow.up.to.line", accessibilityDescription: nil)
        recenterButton.imagePosition = .imageLeading
        recenterButton.isHidden = true
        recenterButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(recenterButton)

        // Top row — the tuning cluster: nudge down / live readout / nudge up,
        // centered as a self-contained stepper. Kept apart from the transport
        // buttons so the readout stays the focal point while tuning by ear.
        let tuningRow = NSStackView(views: [decreaseButton, offsetLabel, increaseButton])
        tuningRow.spacing = 12
        tuningRow.alignment = .centerY
        tuningRow.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tuningRow)

        // Bottom row — transport on the left (replay/scrub while tuning), the
        // Reset / Done actions on the right, pushed apart by a loose spacer.
        let transportRow = NSStackView(views: [seekBackButton, playPauseButton, seekForwardButton])
        transportRow.spacing = 8
        let actionsRow = NSStackView(views: [resetButton, doneButton])
        actionsRow.spacing = 8
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let controlsRow = NSStackView(views: [transportRow, spacer, actionsRow])
        controlsRow.distribution = .fill
        controlsRow.alignment = .centerY
        controlsRow.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(controlsRow)

        NSLayoutConstraint.activate([
            scrollLyricsView.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            scrollLyricsView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scrollLyricsView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scrollLyricsView.bottomAnchor.constraint(equalTo: tuningRow.topAnchor, constant: -12),

            nowBand.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            nowBand.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            nowBand.centerYAnchor.constraint(equalTo: scrollLyricsView.centerYAnchor),
            nowBand.heightAnchor.constraint(equalToConstant: 46),

            noLyricsLabel.centerXAnchor.constraint(equalTo: scrollLyricsView.centerXAnchor),
            noLyricsLabel.centerYAnchor.constraint(equalTo: scrollLyricsView.centerYAnchor),

            recenterButton.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            recenterButton.bottomAnchor.constraint(equalTo: tuningRow.topAnchor, constant: -10),

            tuningRow.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            tuningRow.bottomAnchor.constraint(equalTo: controlsRow.topAnchor, constant: -12),

            controlsRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            controlsRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            controlsRow.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),

            offsetLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
        ])
    }

    private func configureTextButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
    }

    private func configureImageButton(_ button: NSButton, symbol: String, label: String, action: Selector) {
        // Image-only buttons have no title, so without a description VoiceOver reads only "button".
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.setAccessibilityLabel(label)
        button.toolTip = label
        button.imagePosition = .imageOnly
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        scrollLyricsView.delegate = self
        scrollLyricsView.clickToSyncEnabled = true
        scrollLyricsView.bind(\.fontName, withDefaultName: .lyricsWindowFontName)
        scrollLyricsView.bind(\.fontSize, withUnmatchedDefaultName: .lyricsWindowFontSize)
        // Non-current lines read the desktop karaoke's base text color
        // (`.desktopLyricsColor`) so the sync strip and the overlay share one
        // palette and both follow the user's display settings; the synced line
        // keeps its own highlight color.
        scrollLyricsView.bind(\.textColor, withDefaultName: .desktopLyricsColor)
        scrollLyricsView.bind(\.highlightColor, withDefaultName: .lyricsWindowHighlightColor)

        refreshTextContents()
        updatePlayPauseIcon(isPlaying: player.playbackState.isPlaying)

        session.$currentLyrics
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in self.refreshTextContents() }
            .store(in: &cancelBag)
        session.$currentLineIndex
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in self.follow() }
            .store(in: &cancelBag)
        session.$supportingLyrics
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in self.refreshTextContents() }
            .store(in: &cancelBag)
        chineseConverter.converterPublisher
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in self.refreshTextContents() }
            .store(in: &cancelBag)
        explicitResolver.settingsDidChange
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] in self.refreshTextContents() }
            .store(in: &cancelBag)
        player.playbackStateWillChange
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] state in
                self.updatePlayPauseIcon(isPlaying: state.isPlaying)
                // Run the word fill only while playing and on screen; pausing freezes it in place,
                // and `viewWillAppear` restarts it for a window that was closed meanwhile.
                self.follower.setFillActive(state.isPlaying && self.view.window?.isVisible == true)
            }
            .store(in: &cancelBag)

        // Any user scroll means "I'm browsing" — stop following so the strip
        // stays put. Offset is never touched here; only a tap commits.
        observeNotification(
            name: NSScrollView.willStartLiveScrollNotification, object: scrollLyricsView, queue: .main
        ) { [unowned self] _ in self.isFollowing = false }

        // Reflect the offset from any source (tap, buttons, menu stepper, shortcut).
        offsetObservation = session.observe(\.lyricsOffset, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateOffsetLabel()
                // Re-tuning shifts where the fill sits within the line; refresh it
                // so the change is visible immediately, even while paused.
                self.follower.updateHighlight()
            }
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        isFollowing = true
        refreshTextContents()
        updatePlayPauseIcon(isPlaying: player.playbackState.isPlaying)
        follower.setFillActive(player.playbackState.isPlaying)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        follower.setFillActive(false)
    }

    // MARK: - Display

    private func refreshTextContents() {
        let lyrics = session.currentLyrics
        let restoreExplicit = explicitResolver.makeRenderRestoration(
            context: ExplicitRestorationContext(supportingCandidates: session.supportingLyrics)
        )
        scrollLyricsView.setupTextContents(
            lyrics: lyrics,
            converter: chineseConverter.converter,
            restoreExplicit: restoreExplicit
        )
        let hasLyrics = lyrics != nil
        noLyricsLabel.isHidden = hasLyrics
        nowBand.isHidden = !hasLyrics
        [decreaseButton, increaseButton, resetButton].forEach { $0.isEnabled = hasLyrics }
        updateOffsetLabel()
        follow(animated: false)
    }

    private func follow(animated: Bool = true) {
        follower.follow(animated: animated, scrolling: isFollowing)
    }

    private func updateOffsetLabel() {
        offsetLabel.stringValue = String(format: "%+d ms", session.lyricsOffset)
    }

    private func updatePlayPauseIcon(isPlaying: Bool) {
        let symbol = isPlaying ? "pause.fill" : "play.fill"
        let label = isPlaying ? NSLocalizedString("Pause", comment: "sync") : NSLocalizedString("Play", comment: "sync")
        playPauseButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        playPauseButton.setAccessibilityLabel(label)
    }

    // MARK: - Actions

    @objc private func togglePlayPause() { player.playPause() }
    // Re-hear the passage you're tuning: jump back 5s, clamped at the start.
    @objc private func seekBackward() { player.playbackTime = max(0, player.playbackState.time - 5) }
    // Symmetric forward jump, clamped at the track end when its duration is known.
    @objc private func seekForward() {
        let target = player.playbackState.time + 5
        player.playbackTime = (player.currentTrack?.duration).map { min(target, $0) } ?? target
    }
    @objc private func decreaseOffset() { session.lyricsOffset -= 100 }
    @objc private func increaseOffset() { session.lyricsOffset += 100 }
    // Reset clears the offset and snaps back to following the current line, so a
    // reset from a scrolled-away position returns you to where the song is.
    @objc private func resetOffset() {
        session.lyricsOffset = 0
        isFollowing = true
        follow()
    }
    @objc private func done() { view.window?.close() }

    @objc private func recenter() {
        isFollowing = true
        follow()
    }

    /// Re-center on the current line and resume auto-follow. Called when the panel
    /// is (re)shown so it never reappears stuck where the user last scrolled.
    func resumeFollowing() {
        isFollowing = true
        follow(animated: false)
    }

    // MARK: - ScrollLyricsViewDelegate

    func syncToLyricsLine(at position: TimeInterval) {
        guard session.currentLyrics != nil else { return }
        session.lyricsOffset = LyricsOffsetSolver.offsetMilliseconds(
            aligning: position,
            toPlaybackTime: player.playbackState.time,
            appWideOffsetMilliseconds: defaults[.globalLyricsOffset]
        )
        // Preserve the user's follow/browse mode instead of forcing a re-centre.
        // If they've scrolled away to hunt for a line, the click commits without
        // yanking them back (the "Now" pill returns them); if they're following,
        // it re-centres on the synced line as before. `follow()` already scrolls
        // only while `isFollowing`, so this is exactly that.
        follow()
    }

    // Tapping is the sync gesture here; route an accidental double-click to the
    // same alignment rather than seeking.
    func doubleClickLyricsLine(at position: TimeInterval) {
        syncToLyricsLine(at: position)
    }

    func scrollWheelDidStartScroll() { isFollowing = false }
    func scrollWheelDidEndScroll() {}

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        DispatchQueue.main.async { self.follow(animated: false) }
    }
}
