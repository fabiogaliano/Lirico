import AppKit
import Combine
import GenericID
import LiricoFoundation

/// The full-scrollback lyrics shared by the lyrics window and Sync by Ear: keeps a
/// `ScrollLyricsView` showing the current lyrics, highlights the synced line, fills
/// karaoke lines word by word ~30 Hz while playing, and scrolls along while following.
/// The user browses by scrolling away and returns with `resume`.
///
/// Owners keep their layout and actions, and forward their view and window lifecycle.
@MainActor
final class LyricsScrollback {
    /// Called when following starts or stops, to show or hide the owner's Resume pill.
    var onFollowingChange: ((_ isFollowing: Bool) -> Void)?
    /// Called after every rebuild of the text, for the owner's empty state and controls.
    var onContentChange: ((_ hasLyrics: Bool) -> Void)?

    private(set) var isFollowing = true {
        didSet {
            if isFollowing != oldValue { onFollowingChange?(isFollowing) }
        }
    }

    private let scrollView: ScrollLyricsView
    private let nowBand: NSView
    private let player: PlayerHandle
    private let session: LyricsSession
    private let chineseConverter: ChineseConverterProvider
    private let explicitResolver: ExplicitLyricsResolver
    /// Sync by Ear boxes the sung word on karaoke lines, which stands in for the band.
    private let hidesBandOnKaraokeLines: Bool
    // Read by deinit, which isn't main-actor isolated; the owner releases this on main.
    nonisolated(unsafe) private var fillTimer: Timer?
    private var refreshScheduled = false
    /// A closed window skips rebuilds and catches up when it's shown again.
    private var isStale = false
    private var cancelBag = Set<AnyCancellable>()
    nonisolated(unsafe) private var liveScrollObserver: NSObjectProtocol?

    init(
        scrollView: ScrollLyricsView,
        nowBand: NSView,
        player: PlayerHandle,
        session: LyricsSession,
        chineseConverter: ChineseConverterProvider,
        explicitResolver: ExplicitLyricsResolver,
        hidesBandOnKaraokeLines: Bool
    ) {
        self.scrollView = scrollView
        self.nowBand = nowBand
        self.player = player
        self.session = session
        self.chineseConverter = chineseConverter
        self.explicitResolver = explicitResolver
        self.hidesBandOnKaraokeLines = hidesBandOnKaraokeLines
    }

    deinit {
        fillTimer?.invalidate()
        if let liveScrollObserver {
            NotificationCenter.default.removeObserver(liveScrollObserver)
        }
    }

    /// Call from `viewDidLoad`, after setting the callbacks.
    func start() {
        scrollView.bind(\.fontName, withDefaultName: .lyricsWindowFontName)
        scrollView.bind(\.fontSize, withUnmatchedDefaultName: .lyricsWindowFontSize)
        scrollView.bind(\.textColor, withDefaultName: .lyricsWindowTextColor)
        scrollView.bind(\.highlightColor, withDefaultName: .lyricsWindowHighlightColor)

        refresh()

        // The session writes lyrics and their supporting evidence back to back, and each
        // rebuild re-lays out the whole text, so changes are collected into one rebuild.
        Publishers.MergeMany(
            session.$currentLyrics.signal().eraseToAnyPublisher(),
            session.$supportingLyrics.signal().eraseToAnyPublisher(),
            chineseConverter.converterPublisher.signal().eraseToAnyPublisher(),
            explicitResolver.settingsDidChange.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .sink { [unowned self] in self.setNeedsRefresh() }
        .store(in: &cancelBag)
        session.$currentLineIndex
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in self.follow() }
            .store(in: &cancelBag)
        // Run the word fill only while playing and on screen; pausing freezes it in place,
        // and `viewWillAppear` restarts it for a window that was closed meanwhile.
        player.playbackStateWillChange
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] state in
                self.setFillActive(state.isPlaying && self.scrollView.window?.isVisible == true)
            }
            .store(in: &cancelBag)
        // Any user scroll means "I'm browsing": stop following so the text stays put.
        liveScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification, object: scrollView, queue: .main
        ) { [unowned self] _ in MainActor.assumeIsolated { self.browse() } }
    }

    func viewWillAppear() {
        isFollowing = true
        refresh()
        setFillActive(player.playbackState.isPlaying)
    }

    func viewWillDisappear() {
        setFillActive(false)
    }

    /// Resizing moves lines relative to the band; re-center once the new layout lands.
    func viewDidResize() {
        DispatchQueue.main.async { self.follow(animated: false) }
    }

    /// Return to following the synced line.
    func resume(animated: Bool = true) {
        isFollowing = true
        // Window controllers resume when shown; `viewWillAppear` isn't dependable for a reused window.
        if isStale {
            refresh()
        }
        follow(animated: animated)
    }

    /// Stop following; the text stays wherever the user scrolls it.
    func browse() {
        isFollowing = false
    }

    /// Highlight the synced line always; scroll to it only while following.
    func follow(animated: Bool = true) {
        let index = session.currentLineIndex
        updateHighlight()
        guard isFollowing else { return }
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.allowsImplicitAnimation = true
                context.timingFunction = .swiftOut
                self.scrollView.scroll(lineIndex: index)
            }
        } else {
            scrollView.scroll(lineIndex: index)
        }
    }

    /// Paint the current line: a progressive word fill when it carries timetags,
    /// otherwise a whole-line highlight.
    func updateHighlight() {
        let index = session.currentLineIndex
        guard let index,
              let lyrics = session.currentLyrics,
              lyrics.lines.indices.contains(index),
              let timetag = lyrics.lines[index].attachments.timetag,
              !timetag.tags.isEmpty
        else {
            scrollView.highlight(lineIndex: index)
            nowBand.isHidden = session.currentLyrics == nil
            return
        }
        let elapsed = session.adjustedPlaybackTime - lyrics.lines[index].position
        let sung = KaraokeTiming.sungCharacters(elapsed: elapsed, tags: timetag.tags)
        scrollView.highlight(lineIndex: index, sungCharacters: sung)
        nowBand.isHidden = hidesBandOnKaraokeLines
    }

    private func setNeedsRefresh() {
        guard scrollView.window?.isVisible == true else {
            isStale = true
            return
        }
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refresh()
        }
    }

    private func refresh() {
        isStale = false
        let lyrics = session.currentLyrics
        let restoreExplicit = explicitResolver.makeRenderRestoration(
            context: ExplicitRestorationContext(supportingCandidates: session.supportingLyrics)
        )
        scrollView.setupTextContents(
            lyrics: lyrics,
            converter: chineseConverter.converter,
            restoreExplicit: restoreExplicit
        )
        nowBand.isHidden = lyrics == nil
        onContentChange?(lyrics != nil)
        follow(animated: false)
    }

    private func setFillActive(_ active: Bool) {
        fillTimer?.invalidate()
        fillTimer = nil
        guard active else { return }
        // `.common` keeps the fill advancing during scroll/menu tracking runloops.
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHighlight() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fillTimer = timer
        updateHighlight()
    }
}
