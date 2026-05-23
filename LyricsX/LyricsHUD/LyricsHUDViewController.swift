import AppKit
import Combine
import GenericID
import MusicPlayer

class LyricsHUDViewController: NSViewController, NSWindowDelegate, ScrollLyricsViewDelegate, DragNDropDelegate {
    // Storyboard-instantiated; the owning window controller / AppContainer
    // calls `configure(player:session:clock:)` immediately after creation, so
    // these IUOs are guaranteed populated before any subscription fires.
    private var player: PlayerHandle!
    private var session: LyricsSession!
    private var clock: PlaybackClock!

    @IBOutlet var dragNDropView: DragNDropView!
    @IBOutlet var lyricsScrollView: ScrollLyricsView!
    @IBOutlet var noLyricsLabel: NSTextField!

    @IBOutlet var lyricsScrollViewTopMargin: NSLayoutConstraint!
    @IBOutlet var lyricsScrollViewLeftMargin: NSLayoutConstraint!

    @objc dynamic var isTracking = true {
        didSet {
            if !oldValue, isTracking {
                displayLyrics()
            }
        }
    }

    private var isWillTerminate = false

    private var cancelBag = Set<AnyCancellable>()

    override func awakeFromNib() {
        super.awakeFromNib()

        view.window?.do {
            $0.title = "Lyrics Window"
            $0.titlebarAppearsTransparent = true
            $0.styleMask.insert(.borderless)
            $0.delegate = self
        }
        // swiftlint:disable:next force_cast
        let accessory = NSStoryboard.main!.instantiateController(withIdentifier: .lyricsHUDAccessory) as! NSTitlebarAccessoryViewController
        accessory.layoutAttribute = .right
        view.window?.addTitlebarAccessoryViewController(accessory)

        dragNDropView.dragDelegate = self
        lyricsScrollView.delegate = self

        lyricsScrollView.bind(\.fontName, withDefaultName: .lyricsWindowFontName)
        lyricsScrollView.bind(\.fontSize, withUnmatchedDefaultName: .lyricsWindowFontSize)
        lyricsScrollView.bind(\.textColor, withDefaultName: .lyricsWindowTextColor)
        lyricsScrollView.bind(\.highlightColor, withDefaultName: .lyricsWindowHighlightColor)

        observeDefaults(key: .lyricsWindowFontSize, options: [.new, .initial]) { [unowned self] _, change in
            let fontSize = CGFloat(change.newValue)
            self.lyricsScrollViewTopMargin.constant = fontSize
            self.lyricsScrollViewLeftMargin.constant = fontSize
            self.displayLyrics(animation: false)
        }

        observeNotification(
            name: NSScrollView.willStartLiveScrollNotification,
            object: lyricsScrollView,
            queue: .main
        ) { [unowned self] _ in self.isTracking = false }
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate(_:)), name: NSApplication.willTerminateNotification, object: nil)
    }

    /// Wire the HUD to its data sources. The owning window controller must
    /// call this immediately after instantiation; subscriptions live here
    /// rather than in `awakeFromNib` because the session isn't reachable from
    /// inside the storyboard's lifecycle.
    func configure(player: PlayerHandle, session: LyricsSession, clock: PlaybackClock) {
        self.player = player
        self.session = session
        self.clock = clock

        lyricsScrollView.setupTextContents(lyrics: session.currentLyrics)

        // The HUD owns full-scrollback layout, so it observes raw lyrics for now;
        // line-only surfaces consume `displayCoordinator` snapshots.
        session.$currentLyrics
            .signal()
            .receive(on: DispatchQueue.main)
            .invoke(LyricsHUDViewController.lyricsChanged, weaklyOn: self)
            .store(in: &cancelBag)
        session.$currentLineIndex
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in
                self.displayLyrics()
            }.store(in: &cancelBag)
    }

    override func viewWillAppear() {
        noLyricsLabel.isHidden = session?.currentLyrics != nil
        displayLyrics(animation: false)
    }

    // MARK: - Handler

    private func lyricsChanged() {
        DispatchQueue.main.async {
            let newLyrics = self.session.currentLyrics
            self.lyricsScrollView.setupTextContents(lyrics: newLyrics)
            self.noLyricsLabel.isHidden = newLyrics != nil
            self.displayLyrics(animation: false)
        }
    }

    private func displayLyrics(animation: Bool = true) {
        guard let clock else { return }
        let pos = clock.adjustedPlaybackTime
        lyricsScrollView.highlight(position: pos)
        guard isTracking else {
            return
        }
        if animation {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.allowsImplicitAnimation = true
                context.timingFunction = .swiftOut
                self.lyricsScrollView.scroll(position: pos)
            }
        } else {
            lyricsScrollView.scroll(position: pos)
        }
    }

    // MARK: ScrollLyricsViewDelegate

    func doubleClickLyricsLine(at position: TimeInterval) {
        let rawTime = session.currentLyrics?.playbackTime(from: position) ?? position
        player.playbackTime = rawTime
        isTracking = true
    }

    func scrollWheelDidStartScroll() {
        isTracking = false
    }

    func scrollWheelDidEndScroll() {}

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        DispatchQueue.main.async {
            self.displayLyrics(animation: false)
        }
    }

    // MARK: DragNDropDelegate

    func dragFinished(content: String) {
        do {
            try session.importLyrics(content)
        } catch {
            let alert = NSAlert(error: error)
            alert.beginSheetModal(for: view.window!)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard !isWillTerminate else { return }
        defaults[.isShowLyricsHUD] = false
    }

    @objc func applicationWillTerminate(_ notification: Notification) {
        isWillTerminate = true
    }
}

class LyricsHUDAccessoryViewController: NSTitlebarAccessoryViewController {
    @IBAction func lockAction(_ sender: NSButton) {
        if sender.state == .on {
            view.window?.level = .modalPanel
        } else {
            view.window?.level = .normal
        }
    }
}
