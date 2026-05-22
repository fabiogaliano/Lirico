import AppKit
import Combine
import GenericID
import LyricsXFoundation
import MusicPlayer
import OSLog
import MarqueeLabel

class MenuBarLyricsController {
//    let logger = Logger(subsystem: "com.fabiogaliano.LyricsX", category: "MenuBarLyricsController")

    static var shared: MenuBarLyricsController!

    private let player: PlayerHandle

    var statusBarMenu: NSMenu? {
        didSet {
            setupStatusItemMenu()
        }
    }

    private var iconStatusItem: NSStatusItem?
    private var lyricStatusItem: NSStatusItem?
    private var buttonImage: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "LyricsX")?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = true
        return image
    }()
    private var buttonlength: CGFloat = 30

    private let marqueeLabel = MarqueeLabel(frame: .init(x: 0, y: 0, width: 183, height: 22))

    private var lastDisplayMode: DisplayMode?

    private enum DisplayMode {
        case separate
        case combine
    }

    private static let defaultLyric = "LyricsX"

    private var screenLyrics: (lyrics: String, duration: TimeInterval) = (MenuBarLyricsController.defaultLyric, 2) {
        didSet {
            DispatchQueue.main.async {
                self.updateStatusItems()
            }
        }
    }

    private var cancelBag = Set<AnyCancellable>()

    init(player: PlayerHandle) {
        self.player = player
        if !defaults[.hideMenuBarItems] {
            updateStatusItems()
        }
        LyricsSession.shared.displayCoordinator.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.handle(snapshot: snapshot)
            }
            .store(in: &cancelBag)
        workspaceNC
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .signal()
            .receive(on: DispatchQueue.main)
            .invoke(MenuBarLyricsController.updateStatusItems, weaklyOn: self)
            .store(in: &cancelBag)
        defaults.publisher(for: [.menuBarLyricsEnabled, .combinedMenubarLyrics, .hideMenuBarItems])
            .prepend()
            .receive(on: DispatchQueue.main)
            .invoke(MenuBarLyricsController.updateStatusItems, weaklyOn: self)
            .store(in: &cancelBag)
    }

    // Preserves the long-standing menu-bar behavior of NOT clearing the
    // marquee on `.empty` / `.paused` snapshots — the last seen line keeps
    // cycling until a fresh active line replaces it.
    private func handle(snapshot: LyricsDisplaySnapshot) {
        guard snapshot.isLive, let line = snapshot.line else { return }
        if line.primaryText == screenLyrics.lyrics { return }
        screenLyrics = (line.primaryText, line.duration)
    }

    @objc private func updateStatusItems() {
        guard !defaults[.hideMenuBarItems] else {
            marqueeLabel.removeFromSuperview()
            iconStatusItem = nil
            lyricStatusItem = nil
            lastDisplayMode = nil
            return
        }

        guard defaults[.menuBarLyricsEnabled] else {
            marqueeLabel.removeFromSuperview()
            if iconStatusItem == nil {
                setupIconStatusItem()
            }
            lyricStatusItem = nil
            lastDisplayMode = nil
            return
        }

        if defaults[.combinedMenubarLyrics] {
            updateCombinedStatusLyrics()
            lastDisplayMode = .combine
        } else {
            updateSeparateStatusLyrics()
            lastDisplayMode = .separate
        }
    }

    private func updateSeparateStatusLyrics() {
        if lastDisplayMode == nil || lastDisplayMode == .combine {
            setupIconStatusItem()
            setupLyricStatusItem()
        }

        marqueeLabel.setStringValue(screenLyrics.lyrics, lineDisplayTime: screenLyrics.duration)
    }

    private func updateCombinedStatusLyrics() {
        if lastDisplayMode == nil || lastDisplayMode == .separate {
            iconStatusItem = nil
            setupLyricStatusItem()
        }

        marqueeLabel.setStringValue(screenLyrics.lyrics, lineDisplayTime: screenLyrics.duration)
    }

    private func setupLyricStatusItem() {
        marqueeLabel.removeFromSuperview()
        lyricStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        lyricStatusItem?.button?.title = ""
        lyricStatusItem?.button?.image = nil
        lyricStatusItem?.length = NSStatusItem.variableLength
        lyricStatusItem?.button?.frame = marqueeLabel.bounds
        lyricStatusItem?.button?.addSubview(marqueeLabel)
        setupStatusItemMenu()
    }

    private func setupIconStatusItem() {
        iconStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        iconStatusItem?.button?.title = ""
        iconStatusItem?.button?.image = buttonImage
        iconStatusItem?.length = buttonlength
        setupStatusItemMenu()
    }

    private func setupStatusItemMenu() {
        if defaults[.combinedMenubarLyrics] {
            if defaults[.menuBarLyricsEnabled] {
                lyricStatusItem?.menu = statusBarMenu
            } else {
                iconStatusItem?.menu = statusBarMenu
            }
        } else {
            iconStatusItem?.menu = statusBarMenu
        }
    }
}

extension String {
    fileprivate func components(options: String.EnumerationOptions) -> [String] {
        var components: [String] = []
        let range = Range(uncheckedBounds: (startIndex, endIndex))
        enumerateSubstrings(in: range, options: options) { _, _, range, _ in
            components.append(String(self[range]))
        }
        return components
    }
}
