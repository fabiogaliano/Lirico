import AppKit
import Combine
import MusicPlayer
import LyricsXFoundation

class LyricsSession: NSObject {
    private let pipeline: LyricsSearchPipeline
    private let player: PlayerHandle
    private let clock: PlaybackClock
    private let persistenceSettings: PersistenceSettings
    private let searchSettings: SearchSettings
    private let exportSettings: ExportSettings
    private let playerSettings: PlayerSettings
    private let preparation: LyricsPreparation
    private let chineseConverter: ChineseConverterProvider

    /// Resolver for the per-surface `LyricsDisplaySnapshot`. Owned by the
    /// session so consumers reach one well-known place for display state.
    let displayCoordinator: LyricsDisplayCoordinator

    @Published private(set) var currentLyrics: Lyrics? {
        willSet {
            willChangeValue(forKey: "lyricsOffset")
            currentLineIndex = nil
        }
        didSet {
            didChangeValue(forKey: "lyricsOffset")
            clock.setLyrics(currentLyrics)
        }
    }

    @Published var currentLineIndex: Int?

    private var searchRequest: LyricsSearchRequest?
    private var searchTask: Task<Void, Never>?

    private var cancelBag = Set<AnyCancellable>()

    @objc dynamic var lyricsOffset: Int {
        get {
            return currentLyrics?.offset ?? 0
        }
        set {
            currentLyrics?.offset = newValue
            currentLyrics?.metadata.needsPersist = true
            scheduleCurrentLineCheck()
        }
    }

    init(
        player: PlayerHandle,
        clock: PlaybackClock,
        pipeline: LyricsSearchPipeline,
        preparation: LyricsPreparation,
        chineseConverter: ChineseConverterProvider,
        displaySettings: DisplaySettings = DisplaySettings(),
        persistenceSettings: PersistenceSettings = PersistenceSettings(),
        searchSettings: SearchSettings = SearchSettings(),
        exportSettings: ExportSettings = ExportSettings(),
        playerSettings: PlayerSettings = PlayerSettings()
    ) {
        self.pipeline = pipeline
        self.player = player
        self.clock = clock
        self.persistenceSettings = persistenceSettings
        self.searchSettings = searchSettings
        self.exportSettings = exportSettings
        self.playerSettings = playerSettings
        self.preparation = preparation
        self.chineseConverter = chineseConverter
        self.displayCoordinator = LyricsDisplayCoordinator(
            player: player,
            settings: displaySettings,
            chineseConverter: chineseConverter
        )
        super.init()
        displayCoordinator.observe(
            lyrics: $currentLyrics,
            index: $currentLineIndex
        )
        player.currentTrackWillChange
            .signal()
            .receive(on: DispatchQueue.lyricsDisplay)
            .invoke(LyricsSession.currentTrackChanged, weaklyOn: self)
            .store(in: &cancelBag)

        clock.dedupTarget = { [weak self] in self?.currentLineIndex }
        clock.currentLineIndex
            .sink { [weak self] index in self?.currentLineIndex = index }
            .store(in: &cancelBag)

        workspaceNC.publisher(for: NSWorkspace.didTerminateApplicationNotification, object: nil)
            .sink { [playerSettings] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let bundleID = application.bundleIdentifier
                if playerSettings.launchAndQuitWithPlayer, player.designatedPlayerBundleID == bundleID {
                    NSApplication.shared.terminate(self)
                }
            }.store(in: &cancelBag)

        // Run the first track sync on the next runloop tick so callers have a
        // chance to retain the session before subscribers start firing.
        DispatchQueue.main.async { [weak self] in
            self?.currentTrackChanged()
        }
    }

    func scheduleCurrentLineCheck() {
        clock.tick()
    }

    func writeToiTunes(overwrite: Bool) {
        guard let currentLyrics else { return }
        LyricsPersister.writeToiTunes(
            currentLyrics,
            player: player,
            overwrite: overwrite,
            settings: exportSettings,
            converter: chineseConverter.converter
        )
    }

    // MARK: - Persistence policy

    /// Flush the current lyrics to disk when they've been marked dirty
    /// (`metadata.needsPersist == true`). This is the only place in the app
    /// that should drive a disk write — everywhere else asks the session.
    func persistCurrentLyricsIfNeeded() {
        guard let lyrics = currentLyrics, lyrics.metadata.needsPersist else { return }
        LyricsPersister.saveToDisk(lyrics, to: persistenceSettings.storageDirectory())
    }

    /// Persist (if dirty) and reveal the current lyrics file in Finder. Returns
    /// silently if there is no current lyrics or it has no resolvable URL after
    /// the write attempt.
    func revealCurrentLyricsInFinder() {
        persistCurrentLyricsIfNeeded()
        guard let url = currentLyrics?.metadata.localURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Last-chance flush before the app exits. Called from
    /// `AppDelegate.applicationWillTerminate` so the terminate path doesn't
    /// have to know about the `needsPersist` flag.
    func prepareForTermination() {
        persistCurrentLyricsIfNeeded()
    }

    // MARK: - Commands

    /// Adopt `lyrics` as the active selection. When `writeToiTunesIfAuto` is
    /// true and the user has the auto-export preference enabled, push the
    /// lyrics into Apple Music as a side effect (overwriting existing track
    /// lyrics). The track association is read fresh from the player so that
    /// late-arriving callers stay correct.
    func select(_ lyrics: Lyrics, writeToiTunesIfAuto: Bool = false) {
        if let track = player.currentTrack {
            lyrics.associateWithTrack(track)
        }
        currentLyrics = lyrics
        if writeToiTunesIfAuto, exportSettings.writeToiTunesAutomatically {
            writeToiTunes(overwrite: true)
        }
    }

    /// Drop the active lyrics. `deleteOnDisk` covers the "user explicitly
    /// rejected this match" path (wrong lyrics / blocked album): the cached
    /// file is removed, and — when auto-export is on — Apple Music's lyrics
    /// field is cleared so the rejection sticks across restarts. The in-flight
    /// search is always cancelled.
    func clear(deleteOnDisk: Bool = false) {
        if deleteOnDisk {
            if exportSettings.writeToiTunesAutomatically, let track = player.currentTrack {
                track.setLyrics("")
            }
            if let url = currentLyrics?.metadata.localURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        currentLyrics = nil
        searchTask?.cancel()
    }

    func currentTrackChanged() {
        persistCurrentLyricsIfNeeded()
        currentLyrics = nil
        currentLineIndex = nil
        searchTask?.cancel()
        guard let track = player.currentTrack else {
            return
        }
        // FIXME: deal with optional value
        let title = track.title ?? ""
        let artist = track.artist ?? ""

        guard !SearchBlocklist.isBlocked(track: track) else {
            return
        }

        switch LocalLyricsLoader.load(
            track: track,
            title: title,
            artist: artist,
            preparation: preparation,
            settings: persistenceSettings
        ) {
        case .found(let lyrics):
            currentLyrics = lyrics
            return
        case .foundPartial(let lyrics):
            currentLyrics = lyrics
        case .none:
            break
        }

        if let album = track.album, SearchBlocklist.isBlocked(album: album) {
            return
        }

        let duration = track.duration ?? 0
        // Album metadata is included in automatic-track requests so providers
        // like LRCLIB can attempt an exact-match lookup (SR-02). Manual
        // searches omit album to avoid over-constraining user-initiated queries.
        var autoUserInfo: [String: String] = [:]
        if let album = track.album, !album.isEmpty {
            autoUserInfo[LyricsSearchRequest.UserInfoKey.albumName] = album
        }
        let request = LyricsSearchRequest(
            searchTerm: .info(title: title, artist: artist),
            duration: duration,
            limit: 5,
            userInfo: autoUserInfo
        )
        searchRequest = request
        searchTask = Task { @MainActor in
            do {
                var collector = LyricsSelector.shared.makeCollector(window: searchSettings.priorityWindow)

                search: for try await lyrics in pipeline.candidates(for: request) {
                    switch collector.nextDecision() {
                    case .accept:
                        if accept(lyrics: lyrics, request: request) {
                            collector.notifyAccepted()
                        }
                    case .stop:
                        break search
                    }
                }

                if exportSettings.writeToiTunesAutomatically {
                    writeToiTunes(overwrite: true)
                }
            } catch is CancellationError {
                // Search was cancelled due to track change
            } catch {
                print("Failed to fetch lyrics: \(error.localizedDescription)")
            }
        }
    }

    /// Pick `lyrics` as the new selection when it beats the current one for the
    /// still-active request. Returns whether the swap actually happened so the
    /// caller's collection window only starts on a real acceptance.
    private func accept(lyrics: Lyrics, request: LyricsSearchRequest) -> Bool {
        guard searchRequest == request,
              lyrics.metadata.request == request,
              let track = player.currentTrack else {
            return false
        }
        guard LyricsSelector.shared.hasHigherPriority(lyrics, over: currentLyrics, settings: searchSettings) else {
            return false
        }
        lyrics.associateWithTrack(track)
        currentLyrics = lyrics
        return true
    }
}

extension LyricsSession {
    func importLyrics(_ lyricsString: String) throws {
        guard let lrc = Lyrics(lyricsString) else {
            let errorInfo = [
                NSLocalizedDescriptionKey: "Invalid lyric file",
                NSLocalizedRecoverySuggestionErrorKey: "Please try another one.",
            ]
            let error = NSError(domain: lyricsXErrorDomain, code: 0, userInfo: errorInfo)
            throw error
        }
        guard let track = player.currentTrack else {
            let errorInfo = [
                NSLocalizedDescriptionKey: "No music playing",
                NSLocalizedRecoverySuggestionErrorKey: "Play a music and try again.",
            ]
            let error = NSError(domain: lyricsXErrorDomain, code: 0, userInfo: errorInfo)
            throw error
        }
        lrc.metadata.title = track.title
        lrc.metadata.artist = track.artist
        preparation.prepare(lrc)
        lrc.metadata.needsPersist = true
        currentLyrics = lrc
        SearchBlocklist.unblock(track: track)
        SearchBlocklist.unblock(album: track.album ?? "")
    }
}
