import AppKit
import Combine
import GenericID
import LiricoFoundation
import MusicPlayer
import MarqueeLabel

@MainActor
class MenuBarLyricsController {
    private let settings: DisplaySettings

    var statusBarMenu: NSMenu? {
        didSet {
            setupStatusItemMenu()
        }
    }

    private var iconStatusItem: NSStatusItem?
    private var lyricStatusItem: NSStatusItem?
    private var buttonImage: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Lirico")?
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

    private static let defaultLyric = "Lirico"

    private var screenLyrics: (lyrics: String, duration: TimeInterval) = (MenuBarLyricsController.defaultLyric, 2) {
        didSet {
            updateStatusItems()
        }
    }

    private var cancelBag = Set<AnyCancellable>()

    init(display: LyricsDisplayCoordinator, settings: DisplaySettings = DisplaySettings()) {
        self.settings = settings
        if !settings.hideMenuBarItems {
            updateStatusItems()
        }
        // The coordinator assigns `snapshot` on main.
        display.$snapshot
            .sink { [weak self] snapshot in
                self?.handle(snapshot: snapshot)
            }
            .store(in: &cancelBag)
        workspaceNC
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItems() }
            .store(in: &cancelBag)
        defaults.publisher(for: [.menuBarLyricsEnabled, .combinedMenubarLyrics, .hideMenuBarItems])
            .prepend()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateStatusItems() }
            .store(in: &cancelBag)
    }

    // While paused the last line keeps cycling, as it always has, but once the lyrics are
    // gone (new track, rejected, nothing found) the previous song's line must not linger.
    private func handle(snapshot: LyricsDisplaySnapshot) {
        guard snapshot.hasLyrics else {
            if screenLyrics.lyrics != MenuBarLyricsController.defaultLyric {
                screenLyrics = (MenuBarLyricsController.defaultLyric, 2)
            }
            return
        }
        guard snapshot.isLive, let line = snapshot.line else { return }
        if line.primaryText == screenLyrics.lyrics { return }
        screenLyrics = (line.primaryText, line.duration)
    }

    private func updateStatusItems() {
        guard !settings.hideMenuBarItems else {
            marqueeLabel.removeFromSuperview()
            iconStatusItem = nil
            lyricStatusItem = nil
            lastDisplayMode = nil
            return
        }

        guard settings.menuBarLyricsEnabled else {
            marqueeLabel.removeFromSuperview()
            if iconStatusItem == nil {
                setupIconStatusItem()
            }
            lyricStatusItem = nil
            lastDisplayMode = nil
            return
        }

        if settings.combinedMenubarLyrics {
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
        updateLyricAccessibilityLabel()
    }

    private func updateCombinedStatusLyrics() {
        if lastDisplayMode == nil || lastDisplayMode == .separate {
            iconStatusItem = nil
            setupLyricStatusItem()
        }

        marqueeLabel.setStringValue(screenLyrics.lyrics, lineDisplayTime: screenLyrics.duration)
        updateLyricAccessibilityLabel()
    }

    // The lyric item's button has an empty title with the marquee drawn on top, so VoiceOver
    // would otherwise announce an unlabeled button.
    private func updateLyricAccessibilityLabel() {
        let text = screenLyrics.lyrics.isEmpty ? MenuBarLyricsController.defaultLyric : screenLyrics.lyrics
        lyricStatusItem?.button?.setAccessibilityLabel(text)
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
        if settings.combinedMenubarLyrics {
            if settings.menuBarLyricsEnabled {
                lyricStatusItem?.menu = statusBarMenu
            } else {
                iconStatusItem?.menu = statusBarMenu
            }
        } else {
            iconStatusItem?.menu = statusBarMenu
        }
    }
}
