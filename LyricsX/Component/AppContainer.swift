import AppKit
import Combine
import MusicPlayer

/// Composition root for app-wide services and long-lived UI controllers.
///
/// `AppDelegate` constructs a single `AppContainer` after defaults registration.
/// The init body encodes the dependency graph (player → clock → session →
/// controllers) so the previous "order matters" comment in
/// `applicationDidFinishLaunching` becomes type-level wiring instead of an
/// informal contract.
final class AppContainer {
    let player: PlayerHandle
    let playbackClock: PlaybackClock
    let searchPipeline: LyricsSearchPipeline
    let displaySettings: DisplaySettings
    let searchSettings: SearchSettings
    let exportSettings: ExportSettings
    let playerSettings: PlayerSettings
    let session: LyricsSession
    let menuBarController: MenuBarLyricsController
    let karaokeWindowController: KaraokeLyricsWindowController

    private(set) lazy var lyricsHUD: LyricsHUDWindowController = makeLyricsHUD()
    private(set) lazy var searchLyricsWindowController: SearchLyricsWindowController =
        SearchLyricsWindowController(player: player, session: session, pipeline: searchPipeline, searchSettings: searchSettings)
    private(set) lazy var preferencesWindowController: PreferenceWindowController = .create()

    private var touchBarController: TouchBarLyricsController?
    private var touchBarCancellable: AnyCancellable?

    @MainActor
    init(player: PlayerHandle = MusicPlayers.Selected.shared) {
        self.player = player
        let clock = PlaybackClock(player: player)
        self.playbackClock = clock
        let displaySettings = DisplaySettings()
        let searchSettings = SearchSettings()
        let exportSettings = ExportSettings()
        let playerSettings = PlayerSettings()
        self.displaySettings = displaySettings
        self.searchSettings = searchSettings
        self.exportSettings = exportSettings
        self.playerSettings = playerSettings
        let pipeline = LyricsSearchPipeline(settings: searchSettings)
        self.searchPipeline = pipeline
        self.session = LyricsSession(
            player: player,
            clock: clock,
            pipeline: pipeline,
            displaySettings: displaySettings,
            searchSettings: searchSettings,
            exportSettings: exportSettings,
            playerSettings: playerSettings
        )
        self.menuBarController = MenuBarLyricsController(player: player, session: session, settings: displaySettings)
        self.karaokeWindowController = KaraokeLyricsWindowController(
            player: player, session: session, clock: clock, settings: displaySettings
        )
    }

    /// Bring up the surfaces that should appear on app launch. Keeping these
    /// side effects on the container (rather than inside individual inits)
    /// means the constructor stays free of "and now show a window" magic.
    func start(statusBarMenu: NSMenu) {
        LyricsSelector.shared.normalize(against: availableLyricsSources, settings: searchSettings)
        karaokeWindowController.showWindow(nil)
        menuBarController.statusBarMenu = statusBarMenu
        observeTouchBarPreference()
    }

    private func observeTouchBarPreference() {
        touchBarCancellable = defaults.publisher(for: [.touchBarLyricsEnabled])
            .prepend()
            .sink { [weak self] in self?.refreshTouchBar() }
    }

    private func refreshTouchBar() {
        if defaults[.touchBarLyricsEnabled] {
            if touchBarController == nil {
                touchBarController = TouchBarLyricsController(
                    player: player, session: session, clock: playbackClock
                )
            }
        } else {
            touchBarController = nil
        }
    }

    private func makeLyricsHUD() -> LyricsHUDWindowController {
        let wc = LyricsHUDWindowController.create()
        if let vc = wc.contentViewController as? LyricsHUDViewController {
            vc.configure(player: player, session: session)
        }
        return wc
    }
}
