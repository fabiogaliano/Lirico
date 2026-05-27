import AppKit
import Combine
import GenericID
import LyricsXFoundation
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
    private let nowBand = SyncNowBandView()
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
    private var karaokeFillTimer: Timer?

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

        configureImageButton(seekBackButton, symbol: "gobackward.5", action: #selector(seekBackward))
        seekBackButton.toolTip = NSLocalizedString("Back 5 Seconds", comment: "sync")
        configureImageButton(seekForwardButton, symbol: "goforward.5", action: #selector(seekForward))
        seekForwardButton.toolTip = NSLocalizedString("Forward 5 Seconds", comment: "sync")
        configureImageButton(playPauseButton, symbol: "play.fill", action: #selector(togglePlayPause))
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

    private func configureImageButton(_ button: NSButton, symbol: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
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
                // Run the word fill only while playing; pausing freezes it in place.
                self.setKaraokeFill(active: state.isPlaying)
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
                self.updateHighlight(forLineIndex: self.session.currentLineIndex)
            }
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        isFollowing = true
        refreshTextContents()
        updatePlayPauseIcon(isPlaying: player.playbackState.isPlaying)
        setKaraokeFill(active: player.playbackState.isPlaying)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopKaraokeFill()
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

    /// Highlight the synced line always; scroll to it only while following.
    private func follow(animated: Bool = true) {
        let index = session.currentLineIndex
        updateHighlight(forLineIndex: index)
        guard isFollowing else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.allowsImplicitAnimation = true
                context.timingFunction = .swiftOut
                self.scrollLyricsView.scroll(lineIndex: index)
            }
        } else {
            scrollLyricsView.scroll(lineIndex: index)
        }
    }

    /// Paint the current line. When it carries word timetags, fill it
    /// progressively from the offset-adjusted playback time (karaoke style);
    /// otherwise highlight the whole line. Called both on line-index changes
    /// (`follow`) and, while playing, ~30Hz by `karaokeFillTimer` for the
    /// intra-line word fill.
    private func updateHighlight(forLineIndex index: Int?) {
        guard let index,
              let lyrics = session.currentLyrics,
              lyrics.lines.indices.contains(index),
              let timetag = lyrics.lines[index].attachments.timetag,
              !timetag.tags.isEmpty
        else {
            // Line-by-line (or no) lyrics: whole-line highlight, keep the line-wide
            // "now" band — there's no word timing to box.
            scrollLyricsView.highlight(lineIndex: index)
            nowBand.isHidden = session.currentLyrics == nil
            return
        }
        // Karaoke line: fill word-by-word, and let the per-word box (drawn by the
        // scroll view) stand in for the line-wide band, which we hide.
        // Mirror PlaybackClock.adjustedPlaybackTime: per-song offset plus the
        // app-wide offset, so the fill reflects exactly what the user is tuning.
        let adjustedTime = player.playbackState.time
            + Double(session.lyricsOffset + defaults[.globalLyricsOffset]) / 1000.0
        let elapsed = adjustedTime - lyrics.lines[index].position
        let sung = sungCharacters(elapsed: elapsed, tags: timetag.tags)
        scrollLyricsView.highlight(lineIndex: index, sungCharacters: sung)
        nowBand.isHidden = true
    }

    /// Piecewise-linear map from time-into-line to the UTF-16 character the fill
    /// has reached, matching the karaoke overlay: at each tag's `time` the fill
    /// sits at that tag's `index`, interpolated between and clamped at both ends.
    private func sungCharacters(
        elapsed: TimeInterval,
        tags: [LyricsLine.Attachments.InlineTimeTag.Tag]
    ) -> Int {
        guard let first = tags.first else { return 0 }
        if elapsed <= first.time { return first.index }
        for i in 1 ..< tags.count {
            let prev = tags[i - 1]
            let cur = tags[i]
            if elapsed < cur.time {
                let span = cur.time - prev.time
                guard span > 0 else { return cur.index }
                let frac = (elapsed - prev.time) / span
                return prev.index + Int((Double(cur.index - prev.index) * frac).rounded())
            }
        }
        return tags.last!.index
    }

    private func setKaraokeFill(active: Bool) {
        if active {
            startKaraokeFill()
        } else {
            stopKaraokeFill()
        }
    }

    private func startKaraokeFill() {
        karaokeFillTimer?.invalidate()
        // `.common` keeps the fill advancing during scroll/menu tracking runloops.
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateHighlight(forLineIndex: self.session.currentLineIndex)
        }
        RunLoop.main.add(timer, forMode: .common)
        karaokeFillTimer = timer
        updateHighlight(forLineIndex: session.currentLineIndex)
    }

    private func stopKaraokeFill() {
        karaokeFillTimer?.invalidate()
        karaokeFillTimer = nil
    }

    private func updateOffsetLabel() {
        offsetLabel.stringValue = String(format: "%+d ms", session.lyricsOffset)
    }

    private func updatePlayPauseIcon(isPlaying: Bool) {
        let symbol = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
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

/// Translucent strip marking the playback "now" line. Click-through (its
/// `hitTest` returns nil) so taps reach the scroll view beneath it.
private final class SyncNowBandView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
