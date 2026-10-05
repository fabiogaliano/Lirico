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
    // The logo uses a beamed double note with an ascending slant; SF Symbols only offers
    // a single eighth note (`music.note`), so the symbol is drawn as a template path.
    private var buttonImage: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            let sx = bounds.width / 18.0
            let sy = bounds.height / 18.0
            func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: bounds.origin.x + x * sx, y: bounds.origin.y + y * sy)
            }

            let path = NSBezierPath()

            // Left notehead
            let leftCenter = pt(4.4, 4.4)
            let leftTransform = NSAffineTransform()
            leftTransform.translateX(by: leftCenter.x, yBy: leftCenter.y)
            leftTransform.rotate(byDegrees: 25)
            let leftHead = NSBezierPath(ovalIn: NSRect(x: -2.7 * sx, y: -1.9 * sy, width: 5.4 * sx, height: 3.8 * sy))
            leftHead.transform(using: leftTransform as AffineTransform)
            path.append(leftHead)

            // Right notehead
            let rightCenter = pt(11.8, 6.6)
            let rightTransform = NSAffineTransform()
            rightTransform.translateX(by: rightCenter.x, yBy: rightCenter.y)
            rightTransform.rotate(byDegrees: 25)
            let rightHead = NSBezierPath(ovalIn: NSRect(x: -2.7 * sx, y: -1.9 * sy, width: 5.4 * sx, height: 3.8 * sy))
            rightHead.transform(using: rightTransform as AffineTransform)
            path.append(rightHead)

            // Left stem
            let stemWidth: CGFloat = 1.35 * sx
            let leftStem = NSBezierPath(
                roundedRect: NSRect(x: pt(5.6, 4.4).x, y: pt(0, 4.4).y, width: stemWidth, height: 9.8 * sy),
                xRadius: 0.2 * sx,
                yRadius: 0.2 * sy
            )
            path.append(leftStem)

            // Right stem
            let rightStem = NSBezierPath(
                roundedRect: NSRect(x: pt(13.0, 6.6).x, y: pt(0, 6.6).y, width: stemWidth, height: 9.6 * sy),
                xRadius: 0.2 * sx,
                yRadius: 0.2 * sy
            )
            path.append(rightStem)

            // Top beam connecting the two stems
            let beam = NSBezierPath()
            beam.move(to: pt(5.6, 12.0))
            beam.line(to: pt(14.35, 14.2))
            beam.line(to: pt(14.35, 16.5))
            beam.line(to: pt(5.6, 14.3))
            beam.close()
            path.append(beam)

            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Lirico"
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

        showInMarquee(screenLyrics)
        updateLyricAccessibilityLabel()
    }

    private func updateCombinedStatusLyrics() {
        if lastDisplayMode == nil || lastDisplayMode == .separate {
            iconStatusItem = nil
            setupLyricStatusItem()
        }

        showInMarquee(screenLyrics)
        updateLyricAccessibilityLabel()
    }

    /// Lines too long for the item scroll across it; under Reduce Motion they stay put, showing
    /// their start. The label schedules the scroll with `perform(_:with:afterDelay:)`.
    private func showInMarquee(_ lyrics: (lyrics: String, duration: TimeInterval)) {
        marqueeLabel.setStringValue(lyrics.lyrics, lineDisplayTime: lyrics.duration)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSObject.cancelPreviousPerformRequests(withTarget: marqueeLabel)
        }
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
