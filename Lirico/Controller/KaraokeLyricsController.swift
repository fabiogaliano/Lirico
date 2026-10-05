import AppKit
import Combine
import GenericID
import LiricoFoundation
import MusicPlayer
@preconcurrency import SnapKit
import SwiftCF
import CoreGraphicsExt

class KaraokeLyricsWindowController: NSWindowController {
    private static let windowFrame = NSWindow.FrameAutosaveName("KaraokeWindow")

    private var lyricsView = KaraokeLyricsView(frame: .zero)

    private let player: PlayerHandle
    private let clock: PlaybackClock
    private let settings: DisplaySettings

    private var cancelBag = Set<AnyCancellable>()
    // Read by deinit, which isn't main-actor isolated; the controller is only released on main.
    nonisolated(unsafe) private var mouseMonitors: [Any] = []

    init(player: PlayerHandle, display: LyricsDisplayCoordinator, clock: PlaybackClock, settings: DisplaySettings = DisplaySettings()) {
        self.player = player
        self.clock = clock
        self.settings = settings
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isOpaque = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.setFrameUsingName(KaraokeLyricsWindowController.windowFrame, force: true)
        // Without this, moves over the overlay while it accepts events never reach the local monitor.
        window.acceptsMouseMovedEvents = true
        super.init(window: window)

        window.contentView?.addSubview(lyricsView)

        addObserver()
        makeConstraints()

        updateWindowFrame(animate: false)

        lyricsView.displayLrc("Lirico")
        splashActive = true

        // The coordinator assigns `snapshot` on main.
        display.$snapshot
            .sink { [weak self] snapshot in
                guard let self = self else { return }
                self.latestSnapshot = snapshot
                if !self.splashActive {
                    self.renderCurrentSnapshot()
                }
            }
            .store(in: &cancelBag)
        // Turning the overlay back on must re-render: the disabled state rendered nothing, and
        // while paused no new snapshot arrives to replace it.
        defaults.publisher(for: [.preferBilingualLyrics, .desktopLyricsOneLineMode, .desktopLyricsEnabled])
            .prepend()
            .receive(on: DispatchQueue.main)
            .merge(with: clock.offsetChanges)
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

    deinit {
        mouseMonitors.forEach(NSEvent.removeMonitor)
    }

    override func showWindow(_ sender: Any?) {
        // The desktop karaoke surface is a borderless overlay. Asking AppKit
        // to make it key produces a warning because borderless windows cannot
        // become key; we only need it visible.
        window?.orderFront(sender)
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
        ], options: [.initial]) { [unowned self] in
            self.lyricsView.shouldHideWithMouse = self.settings.hideLyricsWhenMousePassingBy && !self.settings.desktopLyricsDraggable
            self.updateMouseMonitors()
            self.updateMouseHandling()
        }
        observeDefaults(keys: [
            .desktopLyricsFontName,
            .desktopLyricsFontSize,
            .desktopLyricsFontNameFallback,
        ], options: [.initial]) { [unowned self] in
            self.lyricsView.font = defaults.desktopLyricsFont
        }

        observeNotification(name: NSApplication.didChangeScreenParametersNotification) { [unowned self] in
            self.updateWindowFrame(animate: true)
        }
        observeNotification(center: workspaceNC, name: NSWorkspace.activeSpaceDidChangeNotification) { [unowned self] in
            self.updateWindowFrame(animate: true)
        }
    }

    private func updateWindowFrame(toScreen: NSScreen? = nil, animate: Bool) {
        let screen = toScreen ?? window?.screen ?? NSScreen.screens[0]
        let fullScreen = screen.isFullScreen || defaults[.desktopLyricsIgnoreSafeArea]
        let frame = fullScreen ? screen.frame : screen.visibleFrame
        window?.setFrame(frame, display: false, animate: animate)
        window?.saveFrame(usingName: KaraokeLyricsWindowController.windowFrame)
    }

    private func updateMouseMonitors() {
        let needsMonitoring = settings.desktopLyricsDraggable || lyricsView.shouldHideWithMouse
        guard needsMonitoring != !mouseMonitors.isEmpty else { return }
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
        guard needsMonitoring else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        // Tracking areas stay silent while the window ignores mouse events, so hover has to be watched from outside.
        // Once the window accepts events, moves over it go to this app instead, and only a local monitor sees the
        // pointer leave the lyrics; without it the overlay would keep swallowing clicks across the whole screen.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.updateMouseHandling()
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.updateMouseHandling()
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func updateMouseHandling() {
        // The window spans the whole screen, and while it accepts mouse events macOS resets the cursor to an arrow
        // over its transparent areas, so links and text fields in apps underneath flicker. Only dragging needs
        // events, and only over the lyrics while ⌘ is held, so plain clicks on the lyrics still reach the app below.
        // A drag already under way keeps the events even if ⌘ is released mid-drag.
        let isDragging = window?.ignoresMouseEvents == false && NSEvent.pressedMouseButtons & 1 != 0
        let wantsDrag = NSEvent.modifierFlags.contains(.command) || isDragging
        let ignores = !(settings.desktopLyricsDraggable && lyricsView.containsMouse && wantsDrag)
        if window?.ignoresMouseEvents != ignores {
            window?.ignoresMouseEvents = ignores
        }
        lyricsView.mouseTest()
    }

    private func renderCurrentSnapshot() {
        let presentation = KaraokeLinePresentation.resolve(
            snapshot: latestSnapshot,
            desktopLyricsEnabled: settings.desktopLyricsEnabled,
            oneLineMode: settings.desktopLyricsOneLineMode,
            preferBilingual: settings.preferBilingualLyrics
        )
        lyricsView.displayLrc(presentation.primary, secondLine: presentation.secondary)

        guard settings.desktopLyricsEnabled,
              latestSnapshot.isLive,
              let line = latestSnapshot.line,
              let upperTextField = lyricsView.displayLine1,
              let timetag = line.line.attachments.timetag else {
            return
        }
        let adjustedPos = clock.adjustedPlaybackTime
        let progress = timetag.tags.map { ($0.time + line.line.position - adjustedPos, $0.index) }
        upperTextField.setProgressAnimation(color: lyricsView.progressColor, progress: progress)
        if !player.playbackState.isPlaying {
            upperTextField.pauseProgressAnimation()
        }
    }

    private func makeConstraints() {
        lyricsView.snp.remakeConstraints { make in
            make.centerX.equalToSuperview().safeMultipliedBy(settings.desktopLyricsXPositionFactor * 2).priority(.low)
            make.centerY.equalToSuperview().safeMultipliedBy(settings.desktopLyricsYPositionFactor * 2).priority(.low)

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
        guard settings.desktopLyricsDraggable,
              let vecToCenter = vecToCenter,
              let window = window else {
            return
        }
        let bounds = window.frame
        let center = event.locationInWindow + vecToCenter
        let centerInScreen = window.convertToScreen(CGRect(origin: center, size: .zero)).origin
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(centerInScreen) }),
           screen != window.screen {
            updateWindowFrame(toScreen: screen, animate: false)
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
        settings.desktopLyricsXPositionFactor = xFactor
        settings.desktopLyricsYPositionFactor = yFactor
        makeConstraints()
        window.layoutIfNeeded()
    }
}

extension NSScreen {
    fileprivate var isFullScreen: Bool {
        guard let windowInfoList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        // Window bounds are in Quartz space (origin top-left of the primary display, y down) and
        // `frame` in Cocoa space (origin bottom-left, y up). They only agree on the primary display.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return !windowInfoList.contains { info in
            guard info[kCGWindowOwnerName as String] as? String == "Window Server",
                  info[kCGWindowName as String] as? String == "Menubar",
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary as CFDictionary?,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                return false
            }
            let cocoaBounds = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            return frame.contains(cocoaBounds)
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
