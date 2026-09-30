import AppKit
import Combine
import MusicPlayer
import LiricoFoundation

// MARK: - LyricsStatus

/// What the session is doing for the current track, so surfaces can tell
/// "still searching" apart from "nothing found" or "blocked" instead of all
/// three looking like an empty screen.
enum LyricsStatus: Equatable {
    case noTrack
    case automationDenied(playerName: String)
    case searching
    case loaded
    case notFound
    case blocked
}

// MARK: - LyricsSession

class LyricsSession: NSObject {
    private let automaticSearch: AutomaticLyricsSearch
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
            // Capture display metadata here, on the main actor (where every
            // metadata write happens), so the display coordinator never reads the
            // live `Lyrics.metadata` dictionary off its background queue. See
            // `LyricsDisplayMetadata`.
            displayMetadata = currentLyrics.map {
                LyricsDisplayMetadata(
                    language: $0.metadata.language,
                    translationLanguages: $0.metadata.translationLanguages
                )
            } ?? .empty
        }
    }

    @Published var currentLineIndex: Int?

    @Published private(set) var status: LyricsStatus = .noTrack

    /// Immutable, main-actor-captured snapshot of the current lyrics' display
    /// metadata, consumed by `LyricsDisplayCoordinator` instead of the live struct.
    @Published private(set) var displayMetadata: LyricsDisplayMetadata = .empty

    /// Other same-song candidates kept as evidence for display-time explicit-word
    /// restoration. This is request-dependent display state, not persisted lyrics
    /// metadata, and is bounded to keep memory predictable. Written only by the
    /// session (automatic search collection, manual select); reset on track change.
    @Published private(set) var supportingLyrics: [Lyrics] = []

    private var searchTask: Task<Void, Never>?

    /// Monotonically-increasing counter. Incremented on every track change,
    /// manual select, and manual clear. Any automatic event that arrives with a
    /// stale generation number is silently dropped, closing the correctness gap
    /// (DEC-007) where late async events could overwrite a user selection.
    private var automaticSearchGeneration: Int = 0

    /// The track the running automatic search belongs to. Track changes reach the
    /// session through a main-actor hop, so a result can land after the player has
    /// already moved on while the generation still matches; this catches that gap.
    private var automaticSearchTrack: MusicTrack?

    private var cancelBag = Set<AnyCancellable>()

    /// Playback position in the current lyrics' timeline (per-song + global offset applied).
    var adjustedPlaybackTime: TimeInterval { clock.adjustedPlaybackTime }

    /// Seek the player to where the current lyrics reach `lyricsPosition`.
    func seek(toLyricsPosition lyricsPosition: TimeInterval) {
        player.playbackTime = clock.playbackTime(atLyricsPosition: lyricsPosition)
    }

    /// Shift the current lyrics so `lyricsPosition` is the line playing right now.
    func align(lyricsPosition: TimeInterval) {
        guard currentLyrics != nil else { return }
        lyricsOffset = clock.songOffset(aligning: lyricsPosition)
    }

    @objc dynamic var lyricsOffset: Int {
        get {
            return currentLyrics?.offset ?? 0
        }
        set {
            currentLyrics?.offset = newValue
            currentLyrics?.metadata.needsPersist = true
            clock.updateSongOffset(newValue)
        }
    }

    init(
        player: PlayerHandle,
        clock: PlaybackClock,
        pipeline: LyricsSearchPipeline,
        preparation: LyricsPreparation,
        chineseConverter: ChineseConverterProvider,
        explicitResolver: ExplicitLyricsResolver = ExplicitLyricsResolver(),
        displaySettings: DisplaySettings = DisplaySettings(),
        persistenceSettings: PersistenceSettings = PersistenceSettings(),
        searchSettings: SearchSettings = SearchSettings(),
        exportSettings: ExportSettings = ExportSettings(),
        playerSettings: PlayerSettings = PlayerSettings()
    ) {
        self.automaticSearch = AutomaticLyricsSearch(pipeline: pipeline, searchSettings: searchSettings)
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
            chineseConverter: chineseConverter,
            explicitResolver: explicitResolver
        )
        super.init()
        displayCoordinator.observe(
            lyrics: $currentLyrics,
            index: $currentLineIndex,
            supporting: $supportingLyrics,
            metadata: $displayMetadata
        )
        // Use the track the player announces instead of re-reading `player.currentTrack`:
        // the announcement is a `willSet` on the player's background queue, so a later read
        // could still return the previous song, re-search it, and strand the new one.
        // The publisher replays the current track on subscribe, which runs the first sync.
        player.currentTrackWillChange
            .removeDuplicates { $0?.id == $1?.id && $0?.title == $1?.title && $0?.artist == $1?.artist }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                MainActor.assumeIsolated {
                    self?.currentTrackChanged(to: track)
                }
            }
            .store(in: &cancelBag)

        clock.lineIndexUpdates
            // Mirror onto the main thread before driving UI. The clock emits on
            // its background queue; assigning the @Published property there let
            // the coordinator-backed surfaces (karaoke, menu bar) and the
            // main-thread surfaces (sync panel, HUD) repaint in nondeterministic
            // order, so at a line boundary one could briefly lead the other by a
            // whole line. A single main-thread origin keeps every surface in step.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                // An index computed for replaced lyrics may be out of range for the new ones.
                guard let self, update.lyrics === self.currentLyrics, self.currentLineIndex != update.index else { return }
                self.currentLineIndex = update.index
            }
            .store(in: &cancelBag)

        workspaceNC.publisher(for: NSWorkspace.didTerminateApplicationNotification, object: nil)
            .sink { [playerSettings] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                guard playerSettings.launchAndQuitWithPlayer, let bundleID = application.bundleIdentifier else { return }
                // The player is picked automatically, so only quit once the last supported one has.
                let players = AutomationPermission.scriptablePlayerBundleIDs
                let otherPlayerRunning = NSWorkspace.shared.runningApplications.contains {
                    $0 != application && !$0.isTerminated && players.contains($0.bundleIdentifier ?? "")
                }
                if players.contains(bundleID), !otherPlayerRunning {
                    NSApplication.shared.terminate(nil)
                }
            }.store(in: &cancelBag)

    }

    func writeToiTunes(overwrite: Bool) {
        guard let track = player.currentTrack else { return }
        writeToiTunes(overwrite: overwrite, to: track)
    }

    private func writeToiTunes(overwrite: Bool, to track: MusicTrack) {
        guard let currentLyrics else { return }
        LyricsPersister.writeToiTunes(
            currentLyrics,
            to: track,
            player: player,
            overwrite: overwrite,
            settings: exportSettings,
            converter: chineseConverter.converter
        )
    }

    // MARK: - Persistence policy

    /// Flush the current lyrics to disk when they've been marked dirty and are
    /// eligible for persistence. This is the only place in the app that should
    /// drive a disk write — everywhere else asks the session.
    func persistCurrentLyricsIfNeeded() {
        guard let lyrics = currentLyrics,
              lyrics.metadata.needsPersist,
              lyrics.metadata.persistenceAllowed else { return }
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
    ///
    /// Manual select cancels any in-flight automatic search by invalidating the
    /// current generation token. Late automatic events arriving after this call
    /// are silently dropped, so automatic finalization/export can never replace
    /// a user-selected result.
    func select(_ lyrics: Lyrics, writeToiTunesIfAuto: Bool = false, supporting: [Lyrics] = []) {
        // Invalidate the current automatic search generation so any pending
        // automatic finalize/export becomes a no-op.
        automaticSearchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil

        if let track = player.currentTrack {
            lyrics.associateWithTrack(track)
        }
        lyrics.metadata.persistenceAllowed = true
        currentLyrics = lyrics
        status = .loaded
        // Retain the manual search's other same-song results as restoration
        // evidence for the chosen lyrics.
        supportingLyrics = SupportingLyrics.bounded(supporting, excluding: lyrics)
        if writeToiTunesIfAuto, exportSettings.writeToiTunesAutomatically {
            writeToiTunes(overwrite: true)
        }
    }

    /// Drop the active lyrics. `deleteOnDisk` covers the "user explicitly
    /// rejected this match" path (wrong lyrics / blocked album): the cached
    /// file is removed, and — when auto-export is on — Apple Music's lyrics
    /// field is cleared so the rejection sticks across restarts. The in-flight
    /// search is always cancelled and the generation invalidated.
    func clear(deleteOnDisk: Bool = false) {
        // Invalidate so any stale automatic event cannot restore what was cleared.
        automaticSearchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil

        if deleteOnDisk {
            if exportSettings.writeToiTunesAutomatically, let track = player.currentTrack {
                track.setLyrics("")
            }
            // Only files Lirico saved itself: a `.lrc` beside the audio file is the
            // user's own, and this app is unsandboxed, so deleting it would be permanent.
            if let url = currentLyrics?.metadata.localURL, persistenceSettings.storageDirectoryContains(url) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        currentLyrics = nil
        supportingLyrics = []
        // Rejecting a match is paired with blocking the track or album, so no search follows.
        status = deleteOnDisk ? .blocked : .notFound
    }

    @MainActor
    func currentTrackChanged(to track: MusicTrack?) {
        persistCurrentLyricsIfNeeded()
        currentLyrics = nil
        currentLineIndex = nil
        supportingLyrics = []

        // Invalidate the previous search so late events from the old track are
        // no-ops even if they arrive after the new task starts.
        automaticSearchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        automaticSearchTrack = track

        guard let track else {
            updateNoTrackStatus()
            return
        }
        // FIXME: deal with optional value
        let title = track.title ?? ""
        let artist = track.artist ?? ""

        guard !SearchBlocklist.isBlocked(track: track) else {
            status = .blocked
            return
        }
        status = .searching

        // Local lookup asks the player for embedded lyrics and the file location over
        // Apple Events and reads disk; off the main thread, a slow player can't stall the UI.
        let generation = automaticSearchGeneration
        let preparation = preparation
        let persistenceSettings = persistenceSettings
        searchTask = Task { @MainActor [weak self] in
            let local = await Task.detached(priority: .userInitiated) {
                LocalLyrics.resolve(
                    track: track,
                    title: title,
                    artist: artist,
                    preparation: preparation,
                    persistenceSettings: persistenceSettings
                )
            }.value
            guard let self, self.isCurrentAutomaticSearch(generation) else { return }
            await self.continueAutomaticSearch(track: track, title: title, artist: artist, local: local, generation: generation)
        }
    }

    @MainActor
    private func continueAutomaticSearch(
        track: MusicTrack,
        title: String,
        artist: String,
        local: LocalLyrics,
        generation: Int
    ) async {
        currentLyrics = local.lyrics
        guard local.needsRemoteSearch else {
            status = .loaded
            return
        }
        if let album = track.album, SearchBlocklist.isBlocked(album: album) {
            status = currentLyrics == nil ? .blocked : .loaded
            return
        }
        status = currentLyrics == nil ? .searching : .loaded

        let initialLyrics = currentLyrics
        await automaticSearch.run(
            AutomaticLyricsSearch.Request(
                title: title,
                artist: artist,
                album: track.album,
                duration: track.duration,
                policy: local.policy
            ),
            isCurrent: { [weak self] in self?.isCurrentAutomaticSearch(generation) ?? false },
            displayed: { [weak self] in self?.currentLyrics },
            report: { [weak self] decision in self?.apply(decision, initialLyrics: initialLyrics) }
        )
    }

    /// Re-checks why no track is visible. Permission can be granted or revoked in System
    /// Settings without any track change reaching the session, so surfaces call this when shown.
    func refreshNoTrackStatus() {
        guard player.currentTrack == nil else { return }
        updateNoTrackStatus()
    }

    private func updateNoTrackStatus() {
        let denied = AutomationPermission.deniedPlayerName(designatedBundleID: player.designatedPlayerBundleID)
        let newStatus: LyricsStatus = denied.map { .automationDenied(playerName: $0) } ?? .noTrack
        if status != newStatus {
            status = newStatus
        }
    }

    // MARK: - Applying automatic search decisions

    private func isCurrentAutomaticSearch(_ generation: Int) -> Bool {
        automaticSearchGeneration == generation && player.currentTrack?.id == automaticSearchTrack?.id
    }

    @MainActor
    private func apply(_ decision: AutomaticLyricsSearch.Decision, initialLyrics: Lyrics?) {
        switch decision {
        // Bind results to the searched track, not the live one, so a change that lands after
        // the currency check can't label, save or export this song's lyrics under the next.
        case .interim(let lyrics):
            // Interim results are display-only: not marked for persistence or exported.
            if let track = automaticSearchTrack {
                lyrics.associateWithTrack(track)
            }
            currentLyrics = lyrics
            status = .loaded

        case .supporting(let supporting):
            updateSupportingLyrics(supporting)

        case .finished(let accepted, let supporting):
            if let accepted {
                if let track = automaticSearchTrack {
                    accepted.associateWithTrack(track)
                }
                accepted.metadata.persistenceAllowed = true
                // Usually already on screen as the interim pick; assigning it again resets
                // the line index and makes the karaoke line blink.
                if accepted !== currentLyrics {
                    currentLyrics = accepted
                }
            }
            updateSupportingLyrics(supporting)
            status = currentLyrics == nil ? .notFound : .loaded
            persistCurrentLyricsIfNeeded()
            // Kept local lyrics are already what the user has; re-exporting them would
            // cost an Apple Event per track and clobber Apple Music's field for nothing.
            if exportSettings.writeToiTunesAutomatically, currentLyrics !== initialLyrics,
               let track = automaticSearchTrack {
                writeToiTunes(overwrite: true, to: track)
            }
        }
    }

    /// Every assignment rebuilds the lyrics window and Sync by Ear text, and the search
    /// reports the same set again as each new candidate arrives.
    private func updateSupportingLyrics(_ supporting: [Lyrics]) {
        guard !supporting.elementsEqual(supportingLyrics, by: ===) else { return }
        supportingLyrics = supporting
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
        // Cancel any in-flight automatic search so it cannot overwrite the
        // user's import — mirrors the same contract as select() and clear().
        // Only after validation, so a bad import leaves the running search alone.
        automaticSearchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil

        lrc.metadata.title = track.title
        lrc.metadata.artist = track.artist
        preparation.prepare(lrc)
        lrc.metadata.needsPersist = true
        lrc.metadata.persistenceAllowed = true
        currentLyrics = lrc
        status = .loaded
        supportingLyrics = []
        SearchBlocklist.unblock(track: track)
        SearchBlocklist.unblock(album: track.album ?? "")
    }
}
