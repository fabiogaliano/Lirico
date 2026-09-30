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
    private let explicitResolver: ExplicitLyricsResolver

    private let dragNDropView = DragNDropView(frame: .zero)
    private let lyricsScrollView = ScrollLyricsView(frame: .zero)
    private let nowBand = LyricsNowBandView()
    private let emptyStateView = NSStackView()
    private let emptyIcon = NSImageView()
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptyHint = NSTextField(labelWithString: "")
    private let emptySearchButton = NSButton()
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
    private lazy var follower = LyricsLineFollower(
        scrollView: lyricsScrollView, nowBand: nowBand, session: session, hidesBandOnKaraokeLines: false
    )

    private var isWillTerminate = false
    private var cancelBag = Set<AnyCancellable>()

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

        emptyTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        emptyTitle.alignment = .center

        emptyHint.font = .systemFont(ofSize: 11)
        emptyHint.alignment = .center
        emptyHint.maximumNumberOfLines = 0

        emptyStateView.orientation = .vertical
        emptyStateView.alignment = .centerX
        emptyStateView.spacing = 6
        emptySearchButton.bezelStyle = .push
        emptySearchButton.controlSize = .small
        emptySearchButton.target = self

        emptyStateView.setViews([emptyIcon, emptyTitle, emptyHint, emptySearchButton], in: .center)
        emptyStateView.setCustomSpacing(12, after: emptyIcon)
        emptyStateView.setCustomSpacing(12, after: emptyHint)
        applyEmptyStateText(for: session.status)
    }

    private func applyEmptyStateText(for status: LyricsStatus) {
        let dropHint = NSLocalizedString("Drag & drop an .lrc file to import", comment: "HUD empty state hint")
        emptySearchButton.action = #selector(openSearchWindow)
        let (title, hint, offersSearch): (String, String, Bool) = switch status {
        case let .automationDenied(playerName):
            (String(format: NSLocalizedString("Lirico Can't See What %@ Is Playing", comment: "HUD empty state title"), playerName),
             NSLocalizedString("Allow Lirico in System Settings → Privacy & Security → Automation.", comment: "HUD empty state hint"),
             true)
        case .noTrack:
            (NSLocalizedString("Nothing Playing", comment: "HUD empty state title"),
             NSLocalizedString("Play a song to see its lyrics", comment: "HUD empty state hint"),
             false)
        case .searching:
            (NSLocalizedString("Searching for Lyrics…", comment: "HUD empty state title"), dropHint, false)
        case .blocked:
            (NSLocalizedString("Lyrics Disabled", comment: "HUD empty state title"),
             NSLocalizedString("Lyrics are turned off for this song or album. Pick some manually to turn them back on.", comment: "HUD empty state hint"),
             true)
        case .notFound, .loaded:
            (NSLocalizedString("No Lyrics", comment: "HUD empty state title"), dropHint, true)
        }
        emptyTitle.stringValue = title
        emptyHint.stringValue = hint
        emptySearchButton.isHidden = !offersSearch
        if case .automationDenied = status {
            emptySearchButton.title = NSLocalizedString("Open System Settings", comment: "HUD empty state button")
            emptySearchButton.action = #selector(openAutomationSettings)
        } else {
            emptySearchButton.title = NSLocalizedString("Search Lyrics…", comment: "HUD empty state button")
        }
    }

    @objc private func openAutomationSettings() {
        AutomationPermission.openSystemSettings()
    }

    @objc private func openSearchWindow() {
        NSApp.sendAction(#selector(AppDelegate.searchLyrics(_:)), to: nil, from: self)
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
        // line-only surfaces consume `LyricsDisplayCoordinator` snapshots.
        session.$currentLyrics
            .signal()
            .receive(on: DispatchQueue.main)
            .invoke(LyricsHUDViewController.lyricsChanged, weaklyOn: self)
            .store(in: &cancelBag)
        session.$currentLineIndex
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in self.follow() }
            .store(in: &cancelBag)
        session.$status
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] in self.applyEmptyStateText(for: $0) }
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
        // Run the word fill only while playing and on screen; pausing freezes it in place,
        // and `viewWillAppear` restarts it for a window that was closed meanwhile.
        player.playbackStateWillChange
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] state in
                self.follower.setFillActive(state.isPlaying && self.view.window?.isVisible == true)
            }
            .store(in: &cancelBag)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        session.refreshNoTrackStatus()
        isTracking = true
        refreshTextContents()
        follower.setFillActive(player.playbackState.isPlaying)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        follower.setFillActive(false)
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

    private func follow(animated: Bool = true) {
        follower.follow(animated: animated, scrolling: isTracking)
    }

    // MARK: - Actions

    @objc private func resume() {
        isTracking = true
        follow()
    }

    // MARK: - ScrollLyricsViewDelegate

    func doubleClickLyricsLine(at position: TimeInterval) {
        session.seek(toLyricsPosition: position)
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
