import AppKit
import Combine
import GenericID
import LiricoFoundation
import MusicPlayer

/// Floating lyrics HUD panel content controller.
///
/// Previously instantiated via storyboard with IBOutlets and an
/// `awakeFromNib`-driven configure flow. Now built programmatically: the
/// window controller injects dependencies in `init`, the view hierarchy is
/// constructed in `loadView`, and subscriptions are wired in `viewDidLoad`.
///
/// Visually it mirrors the Sync by Ear panel — a translucent "now" band frames
/// the current line, the line fills word-by-word when it carries karaoke
/// timing, and a floating "Resume" pill returns to auto-follow after you scroll
/// away. Unlike Sync it never commits an offset: it's a read-only display, so a
/// double-click seeks the player and scrolling only browses.
final class LyricsHUDViewController: NSViewController, NSWindowDelegate, ScrollLyricsViewDelegate, DragNDropDelegate {

    private let player: PlayerHandle
    private let session: LyricsSession
    private let chineseConverter: ChineseConverterProvider
    private let explicitResolver: ExplicitLyricsResolving

    private let dragNDropView = DragNDropView(frame: .zero)
    private let lyricsScrollView = ScrollLyricsView(frame: .zero)
    private let nowBand = LyricsNowBandView()
    private let emptyStateView = NSStackView()
    private let emptyIcon = NSImageView()
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptyHint = NSTextField(labelWithString: "")
    private let resumeButton = NSButton()

    /// `true` while the music drives the scroll position; `false` once the user
    /// scrolls to browse. The "Resume" pill is shown only while browsing.
    @objc dynamic var isTracking = true {
        didSet {
            resumeButton.isHidden = isTracking
            if !oldValue, isTracking { follow() }
        }
    }

    /// Drives the intra-line karaoke fill while playing. Line-index changes alone
    /// are too coarse for word-level progress, so this ticks ~30Hz and repaints
    /// the current line's sung prefix; it's stopped when paused or hidden.
    private var karaokeFillTimer: Timer?

    private var isWillTerminate = false
    private var cancelBag = Set<AnyCancellable>()

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
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 280))
        self.view = root

        for subview in [dragNDropView, lyricsScrollView, nowBand, emptyStateView, resumeButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            // The drag-and-drop layer sits behind everything so a file dropped
            // anywhere in the HUD imports an LRC; the rest stack in front of it.
            root.addSubview(subview)
        }

        configureEmptyState()

        // The "Resume" pill floats over the lyrics and shows only while browsing;
        // it returns to following without seeking. Matches Sync by Ear's pill.
        resumeButton.title = NSLocalizedString("Resume", comment: "HUD resume following")
        resumeButton.image = NSImage(systemSymbolName: "arrow.up.to.line", accessibilityDescription: nil)
        resumeButton.imagePosition = .imageLeading
        resumeButton.bezelStyle = .rounded
        resumeButton.controlSize = .small
        resumeButton.target = self
        resumeButton.action = #selector(resume)
        resumeButton.isHidden = true

        NSLayoutConstraint.activate([
            dragNDropView.topAnchor.constraint(equalTo: root.topAnchor),
            dragNDropView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            dragNDropView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            dragNDropView.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            lyricsScrollView.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            lyricsScrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            lyricsScrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            lyricsScrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),

            nowBand.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            nowBand.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            nowBand.centerYAnchor.constraint(equalTo: lyricsScrollView.centerYAnchor),
            nowBand.heightAnchor.constraint(equalToConstant: 46),

            emptyStateView.centerXAnchor.constraint(equalTo: lyricsScrollView.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: lyricsScrollView.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 16),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16),

            resumeButton.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            resumeButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])
    }

    /// Centered icon + title + hint shown when there are no lyrics. Colors come
    /// from `applyEmptyStateColors()` (the user's configured lyrics text color),
    /// not a fixed value, so the empty state matches the theme the lyrics use.
    private func configureEmptyState() {
        emptyIcon.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: nil)
        emptyIcon.symbolConfiguration = .init(pointSize: 30, weight: .regular)

        emptyTitle.stringValue = NSLocalizedString("No Lyrics", comment: "HUD empty state title")
        emptyTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        emptyTitle.alignment = .center

        emptyHint.stringValue = NSLocalizedString(
            "Drag & drop an .lrc file to import",
            comment: "HUD empty state hint"
        )
        emptyHint.font = .systemFont(ofSize: 11)
        emptyHint.alignment = .center
        emptyHint.maximumNumberOfLines = 0

        emptyStateView.orientation = .vertical
        emptyStateView.alignment = .centerX
        emptyStateView.spacing = 6
        emptyStateView.setViews([emptyIcon, emptyTitle, emptyHint], in: .center)
        emptyStateView.setCustomSpacing(12, after: emptyIcon)
    }

    /// Color the empty state with the same color the lyrics use. `lyricsScrollView`
    /// binds `textColor` to `.desktopLyricsColor` (the lyrics binding owns the key
    /// and its registered default), so reading it back gives the user's color with
    /// no second `defaults` lookup and no hand-written fallback to drift.
    private func applyEmptyStateColors() {
        let color = lyricsScrollView.textColor
        emptyTitle.textColor = color
        emptyHint.textColor = color
        emptyIcon.contentTintColor = color
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        dragNDropView.dragDelegate = self
        lyricsScrollView.delegate = self
        // No word-level syncing here, so skip the per-word box — the karaoke fill
        // already shows progress. (The box is the Sync panel's click feedback.)
        lyricsScrollView.showsWordBox = false

        lyricsScrollView.bind(\.fontName, withDefaultName: .lyricsWindowFontName)
        lyricsScrollView.bind(\.fontSize, withUnmatchedDefaultName: .lyricsWindowFontSize)
        // Base (non-current) lines read the desktop karaoke's color so the HUD, the
        // Sync by Ear strip, and the overlay all share one palette; the current line
        // keeps the lyrics-window highlight color. Mirrors `LyricsSyncViewController`.
        lyricsScrollView.bind(\.textColor, withDefaultName: .desktopLyricsColor)
        lyricsScrollView.bind(\.highlightColor, withDefaultName: .lyricsWindowHighlightColor)

        // Keep the empty state on the same color as the lyrics, live. Observing the
        // scroll view's bound `textColor` (rather than the raw default) means we
        // read the value the binding has already resolved, in any update order.
        observeObject(lyricsScrollView, keyPath: \.textColor, options: [.new, .initial]) { [unowned self] _, _ in
            self.applyEmptyStateColors()
        }

        // Any user scroll means "I'm browsing" — stop following so the strip stays
        // where it was scrolled. `scrollWheelDidStartScroll` covers the same intent
        // for non-inertial wheels; both routes are harmless to keep.
        observeNotification(
            name: NSScrollView.willStartLiveScrollNotification,
            object: lyricsScrollView,
            queue: .main
        ) { [unowned self] _ in self.isTracking = false }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil
        )

        refreshTextContents()

        // The HUD owns full-scrollback layout, so it observes raw lyrics for now;
        // line-only surfaces consume `displayCoordinator` snapshots.
        session.$currentLyrics
            .signal()
            .receive(on: DispatchQueue.main)
            .invoke(LyricsHUDViewController.lyricsChanged, weaklyOn: self)
            .store(in: &cancelBag)
        session.$currentLineIndex
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in self.follow() }
            .store(in: &cancelBag)
        chineseConverter.converterPublisher
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in self.refreshTextContents() }
            .store(in: &cancelBag)
        // Restoration evidence and the lexicon/toggle both affect the full
        // scrollback text, so rebuild contents when either changes.
        session.$supportingLyrics
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in self.refreshTextContents() }
            .store(in: &cancelBag)
        explicitResolver.settingsDidChange
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] in self.refreshTextContents() }
            .store(in: &cancelBag)
        // Run the word fill only while playing; pausing freezes it in place.
        player.playbackStateWillChange
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] state in self.setKaraokeFill(active: state.isPlaying) }
            .store(in: &cancelBag)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        isTracking = true
        refreshTextContents()
        setKaraokeFill(active: player.playbackState.isPlaying)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopKaraokeFill()
    }

    /// Re-center on the current line and resume auto-follow. Called when the panel
    /// is (re)shown so it never reappears stuck where the user last scrolled.
    func resumeFollowing() {
        isTracking = true
        follow(animated: false)
    }

    // MARK: - Display

    private func lyricsChanged() {
        DispatchQueue.main.async { self.refreshTextContents() }
    }

    private func refreshTextContents() {
        let newLyrics = session.currentLyrics
        let restoreExplicit = explicitResolver.makeRenderRestoration(
            context: ExplicitRestorationContext(supportingCandidates: session.supportingLyrics)
        )
        lyricsScrollView.setupTextContents(
            lyrics: newLyrics,
            converter: chineseConverter.converter,
            restoreExplicit: restoreExplicit
        )
        let hasLyrics = newLyrics != nil
        emptyStateView.isHidden = hasLyrics
        nowBand.isHidden = !hasLyrics
        follow(animated: false)
    }

    /// Highlight the synced line always; scroll to it only while following.
    private func follow(animated: Bool = true) {
        let index = session.currentLineIndex
        updateHighlight(forLineIndex: index)
        guard isTracking else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.allowsImplicitAnimation = true
                context.timingFunction = .swiftOut
                self.lyricsScrollView.scroll(lineIndex: index)
            }
        } else {
            lyricsScrollView.scroll(lineIndex: index)
        }
    }

    /// Paint the current line. When it carries word timetags, fill it
    /// progressively from the offset-adjusted playback time (karaoke style);
    /// otherwise highlight the whole line. Either way the "now" band frames the
    /// centered line — unlike the Sync panel the HUD draws no per-word box, since
    /// the fill alone shows progress and there's nothing to sync by word here.
    /// Called both on line-index changes (`follow`) and, while playing, ~30Hz by
    /// `karaokeFillTimer` for the intra-line word fill.
    private func updateHighlight(forLineIndex index: Int?) {
        nowBand.isHidden = session.currentLyrics == nil
        guard let index,
              let lyrics = session.currentLyrics,
              lyrics.lines.indices.contains(index),
              let timetag = lyrics.lines[index].attachments.timetag,
              !timetag.tags.isEmpty
        else {
            lyricsScrollView.highlight(lineIndex: index)
            return
        }
        // Mirror PlaybackClock.adjustedPlaybackTime: per-song offset plus the
        // app-wide offset, so the fill reflects exactly the synced position.
        let adjustedTime = player.playbackState.time
            + Double(session.lyricsOffset + defaults[.globalLyricsOffset]) / 1000.0
        let elapsed = adjustedTime - lyrics.lines[index].position
        let sung = sungCharacters(elapsed: elapsed, tags: timetag.tags)
        lyricsScrollView.highlight(lineIndex: index, sungCharacters: sung)
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
        active ? startKaraokeFill() : stopKaraokeFill()
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

    // MARK: - Actions

    @objc private func resume() {
        isTracking = true
        follow()
    }

    // MARK: - ScrollLyricsViewDelegate

    func doubleClickLyricsLine(at position: TimeInterval) {
        let rawTime = session.currentLyrics?.playbackTime(from: position) ?? position
        player.playbackTime = rawTime
        isTracking = true
    }

    func scrollWheelDidStartScroll() {
        isTracking = false
    }

    func scrollWheelDidEndScroll() {}

    // MARK: - DragNDropDelegate

    func dragFinished(content: String) {
        do {
            try session.importLyrics(content)
        } catch {
            guard let window = view.window else { return }
            let alert = NSAlert(error: error)
            alert.beginSheetModal(for: window)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        DispatchQueue.main.async { self.follow(animated: false) }
    }

    func windowWillClose(_ notification: Notification) {
        guard !isWillTerminate else { return }
        defaults[.isShowLyricsHUD] = false
    }

    @objc func applicationWillTerminate(_ notification: Notification) {
        isWillTerminate = true
    }
}

/// Titlebar accessory hosting the "always on top" lock toggle.
///
/// Programmatic equivalent of the storyboard's "Lyrics HUD Accessory" scene:
/// a small lock button that toggles its window between `.floating` (on, the
/// default — matching the level the panel opens at) and `.normal` (off).
final class LyricsHUDAccessoryViewController: NSTitlebarAccessoryViewController {

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 130, height: 53))

        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.setButtonType(.toggle)
        button.image = NSImage(systemSymbolName: "lock.open", accessibilityDescription: nil)
        button.alternateImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.toolTip = NSLocalizedString("Always on top", comment: "HUD accessory")
        button.state = .on
        button.target = self
        button.action = #selector(lockAction(_:))

        root.addSubview(button)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 14),
            button.heightAnchor.constraint(equalToConstant: 14),
            button.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            root.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: 4),
            button.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor),
        ])

        self.view = root
    }

    @objc func lockAction(_ sender: NSButton) {
        view.window?.level = sender.state == .on ? .floating : .normal
    }
}
