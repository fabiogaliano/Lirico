import AppKit
import Combine
import GenericID
import LyricsXFoundation
import MusicPlayer
import SnapKit
import SwiftCF
import CoreGraphicsExt

class KaraokeLyricsWindowController: NSWindowController {
    private static let windowFrame = NSWindow.FrameAutosaveName("KaraokeWindow")

    private var lyricsView = KaraokeLyricsView(frame: .zero)

    private let player: PlayerHandle

    private var cancelBag = Set<AnyCancellable>()

    init(player: PlayerHandle) {
        self.player = player
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isOpaque = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.setFrameUsingName(KaraokeLyricsWindowController.windowFrame, force: true)
        super.init(window: window)

        window.contentView?.addSubview(lyricsView)

        addObserver()
        makeConstraints()

        updateWindowFrame(animate: false)

        lyricsView.displayLrc("LyricsX")
        splashActive = true

        LyricsSession.shared.displayCoordinator.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self = self else { return }
                self.latestSnapshot = snapshot
                if !self.splashActive {
                    self.renderCurrentSnapshot()
                }
            }
            .store(in: &cancelBag)
        defaults.publisher(for: [.preferBilingualLyrics, .desktopLyricsOneLineMode])
            .prepend()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self, !self.splashActive else { return }
                self.renderCurrentSnapshot()
            }
            .store(in: &cancelBag)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }
            self.splashActive = false
            self.renderCurrentSnapshot()
        }
    }

    private var splashActive = false
    private var latestSnapshot: LyricsDisplaySnapshot = .empty

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addObserver() {
        lyricsView.bind(\.textColor, withDefaultName: .desktopLyricsColor)
        lyricsView.bind(\.progressColor, withDefaultName: .desktopLyricsProgressColor)
        lyricsView.bind(\.shadowColor, withDefaultName: .desktopLyricsShadowColor)
        lyricsView.bind(\.backgroundColor, withDefaultName: .desktopLyricsBackgroundColor)
        lyricsView.bind(\.isVertical, withDefaultName: .desktopLyricsVerticalMode, options: [.nullPlaceholder: false])
        lyricsView.bind(\.drawFurigana, withDefaultName: .desktopLyricsEnableFurigana, options: [.nullPlaceholder: false])
        lyricsView.bind(\.drawRomajin, withDefaultName: .desktopLyricsEnableRomajin, options: [.nullPlaceholder: false])

        let negateOption = [NSBindingOption.valueTransformerName: NSValueTransformerName.negateBooleanTransformerName]
        window?.contentView?.bind(.hidden, withDefaultName: .desktopLyricsEnabled, options: negateOption)

        observeDefaults(key: .disableLyricsWhenSreenShot, options: [.new, .initial]) { [unowned self] _, change in
            self.window?.sharingType = change.newValue ? .none : .readOnly
        }
        observeDefaults(keys: [
            .hideLyricsWhenMousePassingBy,
            .desktopLyricsDraggable,
        ], options: [.initial]) {
            self.lyricsView.shouldHideWithMouse = defaults[.hideLyricsWhenMousePassingBy] && !defaults[.desktopLyricsDraggable]
        }
        observeDefaults(keys: [
            .desktopLyricsFontName,
            .desktopLyricsFontSize,
            .desktopLyricsFontNameFallback,
        ], options: [.initial]) { [unowned self] in
            self.lyricsView.font = defaults.desktopLyricsFont
        }

        observeNotification(name: NSApplication.didChangeScreenParametersNotification, queue: .main) { [unowned self] _ in
            self.updateWindowFrame(animate: true)
        }
        observeNotification(center: workspaceNC, name: NSWorkspace.activeSpaceDidChangeNotification, queue: .main) { [unowned self] _ in
            self.updateWindowFrame(animate: true)
        }
    }

    private func updateWindowFrame(toScreen: NSScreen? = nil, animate: Bool) {
        let screen = toScreen ?? window?.screen ?? NSScreen.screens[0]
        let fullScreen = screen.isFullScreen || defaults.bool(forKey: "DesktopLyricsIgnoreSafeArea")
        let frame = fullScreen ? screen.frame : screen.visibleFrame
        window?.setFrame(frame, display: false, animate: animate)
        window?.saveFrame(usingName: KaraokeLyricsWindowController.windowFrame)
    }

    private func renderCurrentSnapshot() {
        let presentation = KaraokeLinePresentation.resolve(
            snapshot: latestSnapshot,
            desktopLyricsEnabled: defaults[.desktopLyricsEnabled],
            oneLineMode: defaults[.desktopLyricsOneLineMode],
            preferBilingual: defaults[.preferBilingualLyrics]
        )
        lyricsView.displayLrc(presentation.primary, secondLine: presentation.secondary)

        guard defaults[.desktopLyricsEnabled],
              latestSnapshot.isLive,
              let line = latestSnapshot.line,
              let upperTextField = lyricsView.displayLine1,
              let timetag = line.line.attachments.timetag else {
            return
        }
        let adjustedPos = PlaybackClock.shared.adjustedPlaybackTime
        let progress = timetag.tags.map { ($0.time + line.line.position - adjustedPos, $0.index) }
        upperTextField.setProgressAnimation(color: lyricsView.progressColor, progress: progress)
        if !player.playbackState.isPlaying {
            upperTextField.pauseProgressAnimation()
        }
    }

    private func makeConstraints() {
        lyricsView.snp.remakeConstraints { make in
            make.centerX.equalToSuperview().safeMultipliedBy(defaults[.desktopLyricsXPositionFactor] * 2).priority(.low)
            make.centerY.equalToSuperview().safeMultipliedBy(defaults[.desktopLyricsYPositionFactor] * 2).priority(.low)

            make.leading.greaterThanOrEqualToSuperview().priority(.keepWindowSize)
            make.trailing.lessThanOrEqualToSuperview().priority(.keepWindowSize)
            make.top.greaterThanOrEqualToSuperview().priority(.keepWindowSize)
            make.bottom.lessThanOrEqualToSuperview().priority(.keepWindowSize)
        }
    }

    // MARK: Dragging

    private var vecToCenter: CGVector?

    override func mouseDown(with event: NSEvent) {
        let location = lyricsView.convert(event.locationInWindow, from: nil)
        vecToCenter = CGVector(from: location, to: lyricsView.bounds.center)
    }

    override func mouseDragged(with event: NSEvent) {
        guard defaults[.desktopLyricsDraggable],
              let vecToCenter = vecToCenter,
              let window = window else {
            return
        }
        let bounds = window.frame
        var center = event.locationInWindow + vecToCenter
        let centerInScreen = window.convertToScreen(CGRect(origin: center, size: .zero)).origin
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(centerInScreen) }),
           screen != window.screen {
            updateWindowFrame(toScreen: screen, animate: false)
            center = window.convertFromScreen(CGRect(origin: centerInScreen, size: .zero)).origin
            return
        }

        var xFactor = (center.x / bounds.width).clamped(to: 0 ... 1)
        var yFactor = (1 - center.y / bounds.height).clamped(to: 0 ... 1)
        if abs(center.x - bounds.width / 2) < 8 {
            xFactor = 0.5
        }
        if abs(center.y - bounds.height / 2) < 8 {
            yFactor = 0.5
        }
        defaults[.desktopLyricsXPositionFactor] = xFactor
        defaults[.desktopLyricsYPositionFactor] = yFactor
        makeConstraints()
        window.layoutIfNeeded()
    }
}

extension NSScreen {
    fileprivate var isFullScreen: Bool {
        guard let windowInfoList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return !windowInfoList.contains { info in
            guard info[kCGWindowOwnerName as String] as? String == "Window Server",
                  info[kCGWindowName as String] as? String == "Menubar",
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary as CFDictionary?,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                return false
            }
            return frame.contains(bounds)
        }
    }
}

extension ConstraintMakerEditable {
    @discardableResult
    fileprivate func safeMultipliedBy(_ amount: ConstraintMultiplierTarget) -> ConstraintMakerEditable {
        var factor = amount.constraintMultiplierTargetValue
        if factor.isZero {
            factor = .leastNonzeroMagnitude
        }
        return multipliedBy(factor)
    }
}

extension ConstraintPriority {
    static let windowSizeStayPut = ConstraintPriority(NSLayoutConstraint.Priority.windowSizeStayPut.rawValue)
    static let keepWindowSize = ConstraintPriority.windowSizeStayPut.advanced(by: -1)
}

/// Resolves the two text rows the desktop karaoke surface should display.
///
/// Karaoke is the only surface that pairs an active line with a second visible
/// row (translation, next-line preview, or hidden), so this stays local instead
/// of leaking karaoke-only fields into `LyricsDisplaySnapshot`.
struct KaraokeLinePresentation {
    let primary: String
    let secondary: String

    static let empty = KaraokeLinePresentation(primary: "", secondary: "")

    static func resolve(
        snapshot: LyricsDisplaySnapshot,
        desktopLyricsEnabled: Bool,
        oneLineMode: Bool,
        preferBilingual: Bool
    ) -> KaraokeLinePresentation {
        guard desktopLyricsEnabled, snapshot.isLive, let line = snapshot.line else {
            return .empty
        }
        let secondary: String
        if oneLineMode {
            secondary = ""
        } else if preferBilingual, let translation = line.translationText {
            secondary = translation
        } else if let next = line.nextLineText {
            secondary = next
        } else {
            secondary = ""
        }
        return KaraokeLinePresentation(primary: line.primaryText, secondary: secondary)
    }
}
