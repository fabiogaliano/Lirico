import AppKit
import Combine
import MusicPlayer
import ScriptingBridge
import SwiftUI

enum MenuBarSymbolPosition: Int {
    case left
    case right
    case off
}

/// The one-piece menu bar item for the current song, and the artwork panel it opens.
/// Left click toggles the panel; right click opens Lirico's menu.
@MainActor
final class NowPlayingMenuBarItem: NSObject {
    private static let maximumLength: CGFloat = 280
    private static let panelSide: CGFloat = 300

    var menu: NSMenu?

    private let player: PlayerHandle
    private let settings: DisplaySettings
    private let model: NowPlayingPanelModel
    private var statusItem: NSStatusItem?
    private var renderedItem: RenderedItem?
    private var cancelBag = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?
    private var artworkTask: Task<Void, Never>?
    private var artworkTrackID: String?
    private var playerAppBundleID: String?
    private var playerAppURL: URL?

    private lazy var panelContent = NSView(frame: NSRect(x: 0, y: 0, width: Self.panelSide, height: Self.panelSide))
    private lazy var panel = makePanel()

    private struct RenderedItem: Equatable {
        let text: String
        let position: MenuBarSymbolPosition
    }

    init(player: PlayerHandle, settings: DisplaySettings) {
        self.player = player
        self.settings = settings
        self.model = NowPlayingPanelModel(player: player)
        super.init()
        model.openMenu = { [weak self] in self?.openMenu() }
        model.openPlayer = { [weak self] in self?.openPlayer() }
        // Closures written here belong to the main actor, and Swift traps if one runs elsewhere,
        // so each stream must leave the player's queue before its first closure.
        let trackChanges = player.currentTrackWillChange.receive(on: DispatchQueue.main).map { _ in }
        let stateChanges = player.playbackStateWillChange.receive(on: DispatchQueue.main).map { _ in }
        trackChanges.merge(with: stateChanges)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancelBag)
    }

    var isAvailable: Bool {
        settings.nowPlayingMenuBarItemEnabled && player.hasDesignatedPlayer
    }

    func setVisible(_ visible: Bool) {
        guard visible else {
            hidePanel()
            statusItem = nil
            renderedItem = nil
            return
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(handleClick)
            item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
            item.button?.imageHugsTitle = true
            item.button?.lineBreakMode = .byTruncatingTail
            statusItem = item
        }
        refresh()
    }

    private func refresh() {
        guard statusItem != nil else { return }
        model.update()
        updatePlayerApp()
        renderStatusItem()
        if model.isPanelOpen {
            loadArtworkIfNeeded()
        }
    }

    private func renderStatusItem() {
        guard let statusItem, let button = statusItem.button else { return }
        let track = player.currentTrack
        let song = [track?.artist, track?.title]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " - ")
        let rendered = RenderedItem(text: song, position: settings.nowPlayingMenuBarSymbolPosition)
        guard rendered != renderedItem else { return }
        renderedItem = rendered

        button.image = rendered.position == .off ? nil : MenuBarLyricsController.noteImage
        switch (rendered.position, song.isEmpty) {
        case (.off, true):
            // With no symbol and no song the item would be invisible and unclickable.
            button.title = "Lirico"
            button.imagePosition = .noImage
        case (.off, false):
            button.title = song
            button.imagePosition = .noImage
        case (_, true):
            button.title = ""
            button.imagePosition = .imageOnly
        case (.left, false):
            button.title = " " + song
            button.imagePosition = .imageLeft
        case (.right, false):
            button.title = song + " "
            button.imagePosition = .imageRight
        }
        statusItem.length = min(ceil(button.intrinsicContentSize.width) + 8, Self.maximumLength)
    }

    // MARK: - Panel

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            showMenuFromItem()
        } else if model.isPanelOpen {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // The menu is attached only for this click, because while attached it would also take the
    // left click that opens the panel.
    private func showMenuFromItem() {
        guard let statusItem, let menu else { return }
        hidePanel()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// System Now Playing doesn't say which app is playing, so it gets no shortcut.
    private func updatePlayerApp() {
        let bundleID = player.designatedPlayerBundleID
        guard bundleID != playerAppBundleID else { return }
        playerAppBundleID = bundleID
        playerAppURL = bundleID.flatMap(NSWorkspace.shared.urlForApplication(withBundleIdentifier:))
        model.canOpenPlayer = playerAppURL != nil
        model.playerName = playerAppURL?.deletingPathExtension().lastPathComponent ?? ""
        model.playerLogoName = switch player.name {
        case .spotify: "SpotifyIcon"
        case .appleMusic: "AppleMusicIcon"
        default: nil
        }
    }

    private func openPlayer() {
        guard let playerAppURL else { return }
        hidePanel()
        NSWorkspace.shared.openApplication(at: playerAppURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private func showPanel() {
        guard let button = statusItem?.button, let buttonWindow = button.window, let screen = buttonWindow.screen else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let x = min(max(buttonFrame.midX - Self.panelSide / 2, visible.minX + 8), visible.maxX - Self.panelSide - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: buttonFrame.minY - Self.panelSide - 6))

        // A failed download gets another try each time the panel opens.
        if model.artwork == nil {
            artworkTrackID = nil
        }
        model.isPanelOpen = true
        model.update()
        loadArtworkIfNeeded()
        button.highlight(true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        // Only fires for clicks in other apps; clicks on the panel and the item arrive normally.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
    }

    private func hidePanel() {
        guard model.isPanelOpen else { return }
        model.isPanelOpen = false
        panel.orderOut(nil)
        statusItem?.button?.highlight(false)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    private func openMenu() {
        guard let menu else { return }
        let origin = NSPoint(
            x: max(8, panelContent.bounds.width - menu.size.width - 10),
            y: panelContent.bounds.height - 46
        )
        // The panel already names the song. With no song the header stays, because it may be
        // the only place explaining that Lirico lacks permission to see the player.
        let hidesHeader = player.currentTrack != nil
        // `popUp` blocks until the menu closes, which must not happen inside SwiftUI's button action.
        DispatchQueue.main.async { [panelContent] in
            MainMenuBuilder.setNowPlayingHeaderHidden(hidesHeader, in: menu)
            menu.popUp(positioning: nil, at: origin, in: panelContent)
            MainMenuBuilder.setNowPlayingHeaderHidden(false, in: menu)
        }
    }

    private func makePanel() -> NowPlayingPanel {
        let panel = NowPlayingPanel(
            contentRect: panelContent.bounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.onCancel = { [weak self] in self?.hidePanel() }
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: NowPlayingPanelView(model: model, side: Self.panelSide))
        hostingView.frame = panelContent.bounds
        hostingView.autoresizingMask = [.width, .height]
        panelContent.addSubview(hostingView)
        panel.contentView = panelContent
        return panel
    }

    // MARK: - Artwork

    private func loadArtworkIfNeeded() {
        guard let track = player.currentTrack else {
            artworkTask?.cancel()
            artworkTrackID = nil
            model.artwork = nil
            return
        }
        if let artwork = track.artwork {
            artworkTask?.cancel()
            artworkTrackID = track.id
            if model.artwork !== artwork {
                model.artwork = artwork
            }
            return
        }
        guard track.id != artworkTrackID else { return }
        artworkTrackID = track.id
        artworkTask?.cancel()
        // Spotify's scripting interface never fills in the image, only a URL to it.
        guard player.name == .spotify else {
            model.artwork = nil
            return
        }
        let trackID = track.id
        let reference = track.originalSBTrack.map(SpotifyTrackReference.init)
        artworkTask = Task { [weak self] in
            let data = await Self.artworkData(for: reference)
            guard !Task.isCancelled, let self, self.player.currentTrack?.id == trackID else { return }
            self.model.artwork = data.flatMap(NSImage.init(data:))
        }
    }

    private nonisolated static func artworkData(for reference: SpotifyTrackReference?) async -> Data? {
        guard let reference else { return nil }
        // Reading it is a blocking call into Spotify.
        let url = await Task.detached(priority: .utility) { reference.artworkURL }.value
        guard let url else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }
}

// The player library already reads these objects away from the main thread.
private struct SpotifyTrackReference: @unchecked Sendable {
    let track: SBObject

    var artworkURL: URL? {
        guard let value = track.value(forKey: "artworkUrl") as? String,
              let url = URL(string: value),
              url.scheme == "https" else {
            return nil
        }
        return url
    }
}

private final class NowPlayingPanel: NSPanel {
    var onCancel: (() -> Void)?

    // Borderless windows refuse key status by default, and without it Esc never arrives.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

// MARK: - Panel content

@MainActor
private final class NowPlayingPanelModel: ObservableObject {
    @Published var title = ""
    @Published var artist = ""
    @Published var artwork: NSImage?
    @Published var isPlaying = false
    @Published var hasTrack = false
    @Published var duration: TimeInterval?
    @Published var isPanelOpen = false
    @Published var canOpenPlayer = false
    @Published var playerLogoName: String?
    @Published var playerName = ""

    var openMenu: () -> Void = {}
    var openPlayer: () -> Void = {}

    private let player: PlayerHandle

    init(player: PlayerHandle) {
        self.player = player
    }

    var currentTime: TimeInterval {
        let time = max(player.playbackState.time, 0)
        return duration.map { min(time, $0) } ?? time
    }

    func update() {
        let track = player.currentTrack
        hasTrack = track != nil
        title = track?.title ?? NSLocalizedString("Nothing Playing", comment: "menu header when no track is playing")
        artist = track?.artist ?? ""
        // Spotify reports track length in milliseconds, unlike the other players.
        let unitsPerSecond: TimeInterval = player.name == .spotify ? 1000 : 1
        duration = track?.duration.map { $0 / unitsPerSecond }
        isPlaying = player.playbackState.isPlaying
    }

    func previous() { player.skipToPrevious() }
    func playPause() { player.playPause() }
    func next() { player.skipToNext() }
    func seek(to time: TimeInterval) { player.playbackTime = time }
}

private struct NowPlayingPanelView: View {
    @ObservedObject var model: NowPlayingPanelModel
    let side: CGFloat

    @State private var isHovering = false
    @State private var scrubTime: TimeInterval?

    private var showsControls: Bool { isHovering || model.artwork == nil }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            artwork
            if showsControls {
                controls.transition(.opacity)
                menuButton.transition(.opacity)
                playerButton
                    .frame(width: side, height: side, alignment: .topLeading)
                    .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(.white)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = model.artwork {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                // The slight zoom keeps the blur's soft edge outside the panel.
                .scaleEffect(showsControls ? 1.1 : 1)
                .blur(radius: showsControls ? 14 : 0)
                .overlay(Color.black.opacity(showsControls ? 0.32 : 0))
        } else {
            LinearGradient(colors: [Color(white: 0.24), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                .overlay(Image(systemName: "music.note").font(.system(size: 112)).opacity(0.07))
        }
    }

    @ViewBuilder
    private var playerButton: some View {
        if model.canOpenPlayer {
            Button(action: model.openPlayer) {
                playerLogo
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PanelButtonStyle())
            .padding(6)
            .accessibilityLabel(Text("Open \(model.playerName)"))
        }
    }

    // White like the other controls. Players without a one-color logo get a generic "open app" symbol.
    @ViewBuilder
    private var playerLogo: some View {
        if let logoName = model.playerLogoName {
            Image(logoName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "arrow.up.forward.app.fill").font(.system(size: 17))
        }
    }

    private var menuButton: some View {
        Button(action: model.openMenu) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 17))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(PanelButtonStyle())
        .padding(6)
        .accessibilityLabel(Text("Lirico Menu"))
    }

    private var controls: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(model.artist).font(.system(size: 15, weight: .medium)).lineLimit(1).opacity(0.86)
            transport.padding(.vertical, 14)
            Text(model.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Spacer()
            if model.hasTrack, let duration = model.duration, duration > 0 {
                progress(duration: duration)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .frame(width: side, height: side)
    }

    private var transport: some View {
        HStack(spacing: 18) {
            transportButton("backward.fill", size: 25, label: "Previous Track", action: model.previous)
            transportButton(
                model.isPlaying ? "pause.fill" : "play.fill",
                size: 40,
                label: model.isPlaying ? "Pause" : "Play",
                action: model.playPause
            )
            transportButton("forward.fill", size: 25, label: "Next Track", action: model.next)
        }
        .disabled(!model.hasTrack)
        .opacity(model.hasTrack ? 1 : 0.4)
    }

    private func transportButton(_ symbol: String, size: CGFloat, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(PanelButtonStyle())
        .accessibilityLabel(Text(label))
    }

    // Ticks only while the panel is open, so a hidden panel costs nothing during playback.
    @ViewBuilder
    private func progress(duration: TimeInterval) -> some View {
        if model.isPanelOpen {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                progressRow(time: scrubTime ?? model.currentTime, duration: duration)
            }
        } else {
            progressRow(time: model.currentTime, duration: duration)
        }
    }

    private func progressRow(time: TimeInterval, duration: TimeInterval) -> some View {
        HStack(spacing: 10) {
            Text(Self.format(time))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.3)).frame(height: 4)
                    Capsule().fill(.white).frame(width: geometry.size.width * time / duration, height: 4)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubTime = min(max(value.location.x / geometry.size.width, 0), 1) * duration
                        }
                        .onEnded { _ in
                            if let scrubTime { model.seek(to: scrubTime) }
                            scrubTime = nil
                        }
                )
            }
            .frame(height: 16)
            .accessibilityElement()
            .accessibilityLabel(Text("Playback Position"))
            .accessibilityValue(Text(Self.format(time)))
            .accessibilityAdjustableAction { direction in
                let step: TimeInterval = direction == .increment ? 10 : -10
                model.seek(to: min(max(time + step, 0), duration))
            }
            Text(Self.format(duration))
        }
        .font(.system(size: 12).monospacedDigit())
    }

    private static func format(_ time: TimeInterval) -> String {
        let seconds = Int(time)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}
