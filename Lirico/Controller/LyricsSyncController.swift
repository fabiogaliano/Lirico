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
        explicitResolver: ExplicitLyricsResolver
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
        panel.title = NSLocalizedString("Sync by Ear", comment: "sync panel title")
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

    /// The panel is built with a `(0,0)` content rect, which lands in a screen corner,
    /// so it opens where the user left it, or centered.
    override func showWindow(_ sender: Any?) {
        if let window, !window.isVisible {
            window.restoreFrame(named: Self.windowFrame)
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
/// Only a **tap** commits a change: `LyricsSession.align(lyricsPosition:)` shifts
/// the offset so the tapped line is playing now, which re-ticks the clock and
/// live-updates every other surface. Scrolling never touches the offset.
final class LyricsSyncViewController: NSViewController, NSWindowDelegate, ScrollLyricsViewDelegate {

    private let player: PlayerHandle
    private let session: LyricsSession
    private let chineseConverter: ChineseConverterProvider
    private let explicitResolver: ExplicitLyricsResolver

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

    private var cancelBag = Set<AnyCancellable>()
    private var offsetObservation: NSKeyValueObservation?

    /// Set when the panel's own Pause stopped the song, so committing a line or
    /// leaving the panel picks it back up. Cleared once anything resumes playback,
    /// so a pause made in the player itself is never undone from here.
    private var pausedForSync = false

    private lazy var scrollback = LyricsScrollback(
        scrollView: scrollLyricsView,
        nowBand: nowBand,
        player: player,
        session: session,
        chineseConverter: chineseConverter,
        explicitResolver: explicitResolver,
        hidesBandOnKaraokeLines: true
    )

    init(
        player: PlayerHandle,
        session: LyricsSession,
        chineseConverter: ChineseConverterProvider,
        explicitResolver: ExplicitLyricsResolver
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
        offsetLabel.toolTip = NSLocalizedString("This song's offset", comment: "sync readout")

        configureImageButton(seekBackButton, symbol: "gobackward.5", label: NSLocalizedString("Back 5 Seconds", comment: "sync"), action: #selector(seekBackward))
        configureImageButton(seekForwardButton, symbol: "goforward.5", label: NSLocalizedString("Forward 5 Seconds", comment: "sync"), action: #selector(seekForward))
        configureImageButton(playPauseButton, symbol: "play.fill", label: NSLocalizedString("Play", comment: "sync"), action: #selector(togglePlayPause))
        playPauseButton.toolTip = NSLocalizedString("Play / Pause", comment: "sync")
        configureTextButton(decreaseButton, title: "−100", action: #selector(decreaseOffset))
        configureTextButton(increaseButton, title: "+100", action: #selector(increaseOffset))
        // The titles leave out the unit and direction, which the readout between them shows.
        decreaseButton.setAccessibilityLabel(NSLocalizedString("Show lyrics 100 ms later", comment: "sync button"))
        increaseButton.setAccessibilityLabel(NSLocalizedString("Show lyrics 100 ms earlier", comment: "sync button"))
        decreaseButton.toolTip = decreaseButton.accessibilityLabel()
        increaseButton.toolTip = increaseButton.accessibilityLabel()
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
        scrollback.onFollowingChange = { [unowned self] in self.recenterButton.isHidden = $0 }
        scrollback.onContentChange = { [unowned self] hasLyrics in
            self.noLyricsLabel.isHidden = hasLyrics
            [self.decreaseButton, self.increaseButton, self.resetButton].forEach { $0.isEnabled = hasLyrics }
            self.updateOffsetLabel()
        }
        scrollback.start()

        updatePlayPauseIcon(isPlaying: player.playbackState.isPlaying)
        // Only real paused → playing transitions clear `pausedForSync`; a stale
        // "playing" emitted just before our pause lands is deduplicated away.
        player.playbackStateWillChange
            .map(\.isPlaying)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] isPlaying in
                self.updatePlayPauseIcon(isPlaying: isPlaying)
                if isPlaying { self.pausedForSync = false }
            }
            .store(in: &cancelBag)

        // Reflect the offset from any source (tap, buttons, menu stepper, shortcut).
        offsetObservation = session.observe(\.lyricsOffset, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateOffsetLabel()
                // Re-tuning shifts where the fill sits within the line; refresh it
                // so the change is visible immediately, even while paused.
                self.scrollback.updateHighlight()
            }
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        scrollback.viewWillAppear()
        updatePlayPauseIcon(isPlaying: player.playbackState.isPlaying)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        scrollback.viewWillDisappear()
    }

    // MARK: - Display

    private func updateOffsetLabel() {
        offsetLabel.stringValue = String(format: NSLocalizedString("%+d ms", comment: "sync offset readout in milliseconds"), session.lyricsOffset)
    }

    private func updatePlayPauseIcon(isPlaying: Bool) {
        let symbol = isPlaying ? "pause.fill" : "play.fill"
        let label = isPlaying ? NSLocalizedString("Pause", comment: "sync") : NSLocalizedString("Play", comment: "sync")
        playPauseButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        playPauseButton.setAccessibilityLabel(label)
    }

    // MARK: - Actions

    @objc private func togglePlayPause() {
        pausedForSync = player.playbackState.isPlaying
        player.playPause()
    }

    private func resumeIfPausedForSync() {
        guard pausedForSync else { return }
        pausedForSync = false
        if !player.playbackState.isPlaying { player.playPause() }
    }
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
        scrollback.resume()
    }
    @objc private func done() { view.window?.close() }

    @objc private func recenter() {
        scrollback.resume()
    }

    /// Re-center on the current line and resume auto-follow. Called when the panel
    /// is (re)shown so it never reappears stuck where the user last scrolled.
    func resumeFollowing() {
        scrollback.resume(animated: false)
    }

    // MARK: - ScrollLyricsViewDelegate

    func syncToLyricsLine(at position: TimeInterval) {
        session.align(lyricsPosition: position)
        // Preserve the user's follow/browse mode instead of forcing a re-centre.
        // If they've scrolled away to hunt for a line, the click commits without
        // yanking them back (the "Now" pill returns them); if they're following,
        // it re-centres on the synced line as before. `follow()` already scrolls
        // only while following, so this is exactly that.
        scrollback.follow()
        // Picking the line is the confirm step of "pause, find it, tap it".
        resumeIfPausedForSync()
    }

    // Tapping is the sync gesture here; route an accidental double-click to the
    // same alignment rather than seeking.
    func doubleClickLyricsLine(at position: TimeInterval) {
        syncToLyricsLine(at: position)
    }

    func scrollWheelDidStartScroll() { scrollback.browse() }
    func scrollWheelDidEndScroll() {}

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        scrollback.viewDidResize()
    }

    // Done, the close button and ⌘W all end here.
    func windowWillClose(_ notification: Notification) {
        resumeIfPausedForSync()
    }
}
