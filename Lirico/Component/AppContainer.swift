import AppKit
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
    private let playbackClock: PlaybackClock
    private let searchPipeline: LyricsSearchPipeline
    private let displaySettings: DisplaySettings
    private let searchSettings: SearchSettings
    private let exportSettings: ExportSettings
    private let playerLifecycle: PlayerLifecycle
    private let lyricsFilter: LyricsFilter
    private let lyricsPreparation: LyricsPreparation
    private let chineseConverterProvider: ChineseConverterProvider
    private let explicitResolver: ExplicitLyricsResolver
    let session: LyricsSession
    private let menuBarController: MenuBarLyricsController
    private let karaokeWindowController: KaraokeLyricsWindowController

    private(set) lazy var lyricsHUD: LyricsHUDWindowController = LyricsHUDWindowController(
        player: player,
        session: session,
        chineseConverter: chineseConverterProvider,
        explicitResolver: explicitResolver
    )
    private(set) lazy var lyricsSync: LyricsSyncWindowController = LyricsSyncWindowController(
        player: player,
        session: session,
        chineseConverter: chineseConverterProvider,
        explicitResolver: explicitResolver
    )
    private(set) lazy var searchLyricsWindowController: SearchLyricsWindowController =
        SearchLyricsWindowController(player: player, session: session, pipeline: searchPipeline, searchSettings: searchSettings)
    private(set) lazy var preferencesWindowController: PreferenceWindowController = .create()
    private(set) lazy var aboutWindowController: AboutWindowController = AboutWindowController()

    @MainActor
    init(player: PlayerHandle = SelectedPlayerHandle()) {
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
        self.playerLifecycle = PlayerLifecycle(settings: playerSettings)
        let lyricsFilter = LyricsFilter()
        let preparation = LyricsPreparation(filter: lyricsFilter)
        let chineseConverter = ChineseConverterProvider()
        let explicitResolver = ExplicitLyricsResolver()
        self.lyricsFilter = lyricsFilter
        self.lyricsPreparation = preparation
        self.chineseConverterProvider = chineseConverter
        self.explicitResolver = explicitResolver
        let pipeline = LyricsSearchPipeline(settings: searchSettings, preparation: preparation)
        self.searchPipeline = pipeline
        let display = LyricsDisplayCoordinator(
            player: player,
            settings: displaySettings,
            chineseConverter: chineseConverter,
            explicitResolver: explicitResolver
        )
        self.session = LyricsSession(
            player: player,
            clock: clock,
            automaticSearch: AutomaticLyricsSearch(pipeline: pipeline, searchSettings: searchSettings),
            display: display,
            preparation: preparation,
            chineseConverter: chineseConverter,
            persistenceSettings: PersistenceSettings(),
            exportSettings: exportSettings
        )
        self.menuBarController = MenuBarLyricsController(display: display, settings: displaySettings)
        self.karaokeWindowController = KaraokeLyricsWindowController(
            player: player, display: display, clock: clock, settings: displaySettings
        )
    }

    /// Bring up the surfaces that should appear on app launch. Keeping these
    /// side effects on the container (rather than inside individual inits)
    /// means the constructor stays free of "and now show a window" magic.
    func start(statusBarMenu: NSMenu) {
        searchSettings.normalizeSourcePriorityOrder()
        playerLifecycle.start()
        karaokeWindowController.showWindow(nil)
        menuBarController.statusBarMenu = statusBarMenu
    }
}
