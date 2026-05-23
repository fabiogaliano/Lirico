import AppKit
import Combine
import GenericID
import MusicPlayer

/// Floating lyrics HUD panel content controller.
///
/// Previously instantiated via storyboard with IBOutlets and an
/// `awakeFromNib`-driven configure flow. Now built programmatically: the
/// window controller injects dependencies in `init`, the view hierarchy is
/// constructed in `loadView`, and subscriptions are wired in `viewDidLoad`.
final class LyricsHUDViewController: NSViewController, NSWindowDelegate, ScrollLyricsViewDelegate, DragNDropDelegate {

    private let player: PlayerHandle
    private let session: LyricsSession
    private let chineseConverter: ChineseConverterProvider

    private let dragNDropView = DragNDropView(frame: .zero)
    private let lyricsScrollView = ScrollLyricsView(frame: .zero)
    private let noLyricsLabel = NSTextField(labelWithString: "")
    private let trackingButton = NSButton()

    private var lyricsScrollViewTopMargin: NSLayoutConstraint!
    private var lyricsScrollViewLeftMargin: NSLayoutConstraint!

    @objc dynamic var isTracking = true {
        didSet {
            if !oldValue, isTracking {
                displayLyrics()
            }
        }
    }

    private var isWillTerminate = false
    private var cancelBag = Set<AnyCancellable>()

    init(player: PlayerHandle, session: LyricsSession, chineseConverter: ChineseConverterProvider) {
        self.player = player
        self.session = session
        self.chineseConverter = chineseConverter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 280))
        self.view = root

        dragNDropView.translatesAutoresizingMaskIntoConstraints = false
        lyricsScrollView.translatesAutoresizingMaskIntoConstraints = false
        noLyricsLabel.translatesAutoresizingMaskIntoConstraints = false
        trackingButton.translatesAutoresizingMaskIntoConstraints = false

        // The drag-and-drop layer sits behind everything so file drops anywhere
        // in the HUD import an LRC.
        root.addSubview(dragNDropView)
        root.addSubview(lyricsScrollView)
        root.addSubview(noLyricsLabel)
        root.addSubview(trackingButton)

        noLyricsLabel.alignment = .center
        noLyricsLabel.font = .systemFont(ofSize: 15)
        noLyricsLabel.textColor = .white
        noLyricsLabel.maximumNumberOfLines = 0
        noLyricsLabel.lineBreakMode = .byWordWrapping
        noLyricsLabel.stringValue = NSLocalizedString(
            "No Lyrics\n\nDrag & Drop to import LRC file",
            comment: "HUD empty state"
        )

        trackingButton.bezelStyle = .shadowlessSquare
        trackingButton.isBordered = false
        trackingButton.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        trackingButton.imagePosition = .imageOnly
        trackingButton.imageScaling = .scaleProportionallyUpOrDown
        trackingButton.toolTip = NSLocalizedString("Synchronism", comment: "HUD button")
        trackingButton.keyEquivalent = " "
        trackingButton.setButtonType(.momentaryChange)

        // Top/left margins are recomputed when font size changes (see
        // observeDefaults in viewDidLoad); start at zero and let the observer
        // populate them on first emission.
        lyricsScrollViewTopMargin = lyricsScrollView.topAnchor.constraint(equalTo: root.topAnchor, constant: 8)
        lyricsScrollViewLeftMargin = lyricsScrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8)

        NSLayoutConstraint.activate([
            dragNDropView.topAnchor.constraint(equalTo: root.topAnchor),
            dragNDropView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            dragNDropView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            dragNDropView.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            lyricsScrollViewTopMargin,
            lyricsScrollViewLeftMargin,
            lyricsScrollView.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            lyricsScrollView.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            lyricsScrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            lyricsScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),

            noLyricsLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            noLyricsLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),

            trackingButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            root.bottomAnchor.constraint(equalTo: trackingButton.bottomAnchor, constant: 8),
            trackingButton.widthAnchor.constraint(equalToConstant: 16),
            trackingButton.heightAnchor.constraint(equalToConstant: 16),
        ])

        // Tracking button mirrors `self.isTracking` for both value and hidden
        // state — when actively tracking we hide the sync button (storyboard
        // had `hidden = self.isTracking` and `value = self.isTracking`).
        trackingButton.bind(.value, to: self, withKeyPath: "isTracking", options: nil)
        trackingButton.bind(.hidden, to: self, withKeyPath: "isTracking", options: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil
        )

        refreshTextContents()

        // The HUD owns full-scrollback layout, so it observes raw lyrics for
        // now; line-only surfaces consume `displayCoordinator` snapshots.
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
        chineseConverter.converterPublisher
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in
                self.refreshTextContents()
            }.store(in: &cancelBag)
    }

    override func viewWillAppear() {
        noLyricsLabel.isHidden = session.currentLyrics != nil
        displayLyrics(animation: false)
    }

    // MARK: - Handler

    private func lyricsChanged() {
        DispatchQueue.main.async {
            self.refreshTextContents()
        }
    }

    private func refreshTextContents() {
        let newLyrics = session.currentLyrics
        lyricsScrollView.setupTextContents(
            lyrics: newLyrics,
            converter: chineseConverter.converter
        )
        noLyricsLabel.isHidden = newLyrics != nil
        displayLyrics(animation: false)
    }

    private func displayLyrics(animation: Bool = true) {
        let index = session.currentLineIndex
        lyricsScrollView.highlight(lineIndex: index)
        guard isTracking else {
            return
        }
        if animation {
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
            guard let window = view.window else { return }
            let alert = NSAlert(error: error)
            alert.beginSheetModal(for: window)
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

/// Titlebar accessory hosting the "always on top" lock toggle.
///
/// Programmatic equivalent of the storyboard's "Lyrics HUD Accessory"
/// scene: 14×14 button, lock.open/lock.fill alternate images, toggles its
/// hosting window between `.normal` and `.modalPanel` levels.
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
        if sender.state == .on {
            view.window?.level = .modalPanel
        } else {
            view.window?.level = .normal
        }
    }
}
