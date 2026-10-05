import AppKit
import MusicPlayer

/// Composition root for app-wide services and long-lived UI controllers.
///
/// `AppDelegate` constructs a single `AppContainer` after defaults registration.
/// The init body encodes the dependency graph (player → clock → session →
/// controllers), so construction order is enforced by the types rather than by
/// convention.
@MainActor
final class AppContainer {
    let player: PlayerHandle
    private let searchPipeline: LyricsSearchPipeline
    private let searchSettings: SearchSettings
    private let playerLifecycle: PlayerLifecycle
    private let chineseConverterProvider: ChineseConverterProvider
    private let explicitResolver: ExplicitLyricsResolver
    let session: LyricsSession
    /// Held here because nothing else keeps it alive: the session only wires its inputs, and
    /// the surfaces only subscribe to its snapshot.
    private let display: LyricsDisplayCoordinator
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

    init(player: PlayerHandle = SelectedPlayerHandle()) {
        self.player = player
        let clock = PlaybackClock(player: player)
        let displaySettings = DisplaySettings()
        let searchSettings = SearchSettings()
        let exportSettings = ExportSettings()
        self.searchSettings = searchSettings
        self.playerLifecycle = PlayerLifecycle(settings: PlayerSettings())
        let preparation = LyricsPreparation(filter: LyricsFilter())
        let chineseConverter = ChineseConverterProvider()
        let explicitResolver = ExplicitLyricsResolver()
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
        self.display = display
        self.session = LyricsSession(
            player: player,
            clock: clock,
            automaticSearch: AutomaticLyricsSearch(pipeline: pipeline, searchSettings: searchSettings),
            display: display,
            preparation: preparation,
            chineseConverter: chineseConverter,
            persistenceSettings: PersistenceSettings(),
            exportSettings: exportSettings,
            blocklist: SearchBlocklist()
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
