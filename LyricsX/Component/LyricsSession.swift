import AppKit
import Combine
import MusicPlayer
import LyricsXFoundation

class LyricsSession: NSObject {
    static var shared: LyricsSession!

    var lyricsManager: LyricsProvider
    private let player: PlayerHandle

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
            PlaybackClock.shared.setLyrics(currentLyrics)
        }
    }

    @Published var currentLineIndex: Int?

    var searchRequest: LyricsSearchRequest?
    var searchTask: Task<Void, Never>?

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

    init(player: PlayerHandle) {
        self.lyricsManager = LyricsProviders.Group()
        self.player = player
        self.displayCoordinator = LyricsDisplayCoordinator(player: player)
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

        PlaybackClock.shared.dedupTarget = { [weak self] in self?.currentLineIndex }
        PlaybackClock.shared.currentLineIndex
            .sink { [weak self] index in self?.currentLineIndex = index }
            .store(in: &cancelBag)

        workspaceNC.publisher(for: NSWorkspace.didTerminateApplicationNotification, object: nil)
            .sink { notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let bundleID = application.bundleIdentifier
                if defaults[.launchAndQuitWithPlayer], player.designatedPlayerBundleID == bundleID {
                    NSApplication.shared.terminate(self)
                }
            }.store(in: &cancelBag)
        // Defer the initial sync: setting currentLyrics here would re-enter
        // LyricsSession.shared via PlaybackClock.tick() while dispatch_once is
        // still in flight, which libdispatch traps as recursive locking.
        DispatchQueue.main.async { [weak self] in
            self?.currentTrackChanged()
        }

        Task {
            try await updateLyricsManager()
        }
    }

    @MainActor
    func updateLyricsManager() async throws {
        let services: [LyricsProviders.Service] = LyricsProviders.Service.noAuthenticationRequiredServices

        var providers: [LyricsProvider] = []
        for service in services {
            providers.append(service.create())
        }

        // Add Musixmatch provider with saved token if available
        if let token = defaults[.musixmatchToken], !token.isEmpty {
            let musixmatchProvider = LyricsProviders.Musixmatch(usertoken: token)
            providers.append(musixmatchProvider)
        }

        lyricsManager = LyricsProviders.Group(providers: providers)
    }

    func scheduleCurrentLineCheck() {
        PlaybackClock.shared.tick()
    }

    func writeToiTunes(overwrite: Bool) {
        guard let currentLyrics else { return }
        LyricsPersister.writeToiTunes(currentLyrics, player: player, overwrite: overwrite)
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
        if writeToiTunesIfAuto, defaults[.writeToiTunesAutomatically] {
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
            if defaults[.writeToiTunesAutomatically], let track = player.currentTrack {
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
        if currentLyrics?.metadata.needsPersist == true {
            currentLyrics?.persist()
        }
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

        switch LocalLyricsLoader.load(track: track, title: title, artist: artist) {
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
        let request = LyricsSearchRequest(searchTerm: .info(title: title, artist: artist), duration: duration, limit: 5)
        searchRequest = request
        searchTask = Task { @MainActor in
            do {
                let window = defaults[.lyricsPriorityWindow] ?? 5
                var collector = LyricsSelector.shared.makeCollector(window: window)

                search: for try await lyrics in lyricsManager.lyrics(for: request) {
                    switch collector.nextDecision() {
                    case .accept:
                        let before = currentLyrics
                        lyricsReceived(lyrics: lyrics)
                        if currentLyrics !== before {
                            collector.notifyAccepted()
                        }
                    case .stop:
                        break search
                    }
                }

                if defaults[.writeToiTunesAutomatically] {
                    writeToiTunes(overwrite: true)
                }
            } catch is CancellationError {
                // Search was cancelled due to track change
            } catch {
                print("Failed to fetch lyrics: \(error.localizedDescription)")
            }
        }
    }

    // MARK: LyricsSourceDelegate

    func lyricsReceived(lyrics: Lyrics) {
        guard let req = searchRequest,
              lyrics.metadata.request == req,
              let track = player.currentTrack else {
            return
        }
        if defaults[.strictSearchEnabled], !lyrics.isMatched() {
            return
        }
        if !LyricsSelector.shared.hasHigherPriority(lyrics, over: currentLyrics) {
            return
        }

        lyrics.associateWithTrack(track)
        LyricsPreparer.prepare(lyrics)
        lyrics.metadata.needsPersist = true
        currentLyrics = lyrics
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
        LyricsPreparer.prepare(lrc)
        lrc.metadata.needsPersist = true
        currentLyrics = lrc
        SearchBlocklist.unblock(track: track)
        SearchBlocklist.unblock(album: track.album ?? "")
    }
}
