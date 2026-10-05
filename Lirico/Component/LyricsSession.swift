import AppKit
import Combine
// `MusicTrack` isn't marked Sendable; the local lookup only reads it off the main thread.
@preconcurrency import MusicPlayer
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
    case blocked(LyricsSession.RejectionScope)
}

// MARK: - LyricsSession

@MainActor
class LyricsSession: NSObject {
    private let automaticSearch: AutomaticLyricsSearch
    private let player: PlayerHandle
    private let clock: PlaybackClock
    private let persistenceSettings: PersistenceSettings
    private let exportSettings: ExportSettings
    private let blocklist: SearchBlocklist
    private let preparation: LyricsPreparation
    private let chineseConverter: ChineseConverterProvider

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

    @Published private(set) var currentLineIndex: Int?

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

    /// Monotonically-increasing counter. Incremented on every track change, manual
    /// select, import and rejection. Any automatic event that arrives with a stale
    /// generation number is silently dropped, so a late result can't overwrite what
    /// the user chose.
    private var automaticSearchGeneration: Int = 0

    /// The track the running automatic search belongs to. Track changes reach the
    /// session through a main-actor hop, so a result can land after the player has
    /// already moved on while the generation still matches; this catches that gap.
    private var automaticSearchTrack: MusicTrack?
    /// Set when a block stopped the search for the current track. The status alone can't
    /// tell: an album block with local lyrics leaves it `.loaded`.
    private var searchStoppedByBlock = false

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
        automaticSearch: AutomaticLyricsSearch,
        display: LyricsDisplayCoordinator,
        preparation: LyricsPreparation,
        chineseConverter: ChineseConverterProvider,
        persistenceSettings: PersistenceSettings,
        exportSettings: ExportSettings,
        blocklist: SearchBlocklist
    ) {
        self.automaticSearch = automaticSearch
        self.player = player
        self.clock = clock
        self.persistenceSettings = persistenceSettings
        self.exportSettings = exportSettings
        self.blocklist = blocklist
        self.preparation = preparation
        self.chineseConverter = chineseConverter
        super.init()
        display.observe(
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
            // @Sendable keeps this off the main actor: it runs on the player's queue, before the hop.
            .removeDuplicates { @Sendable in $0?.id == $1?.id && $0?.title == $1?.title && $0?.artist == $1?.artist }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.currentTrackChanged(to: track)
            }
            .store(in: &cancelBag)

        blocklist.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.searchAgainIfUnblocked()
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
    }

    var canWriteToAppleMusic: Bool {
        guard currentLyrics != nil, let track = player.currentTrack else { return false }
        return canWriteToAppleMusic(track)
    }

    /// A track only takes lyrics while Apple Music is the player and still playing it.
    private func canWriteToAppleMusic(_ track: MusicTrack) -> Bool {
        player.name == .appleMusic && player.currentTrack?.id == track.id
    }

    func writeToiTunes() {
        guard let track = player.currentTrack else { return }
        writeToiTunes(to: track)
    }

    private func writeToiTunes(to track: MusicTrack) {
        guard let currentLyrics, canWriteToAppleMusic(track) else { return }
        LyricsPersister.writeToiTunes(
            currentLyrics,
            to: track,
            settings: exportSettings,
            converter: chineseConverter.converter
        )
    }

    // MARK: - Persistence policy

    /// Flush the current lyrics to disk when they've been marked dirty and are
    /// eligible for persistence. This is the only place in the app that should
    /// drive a disk write — everywhere else asks the session.
    @discardableResult
    private func persistCurrentLyricsIfNeeded() -> Task<Void, Never>? {
        guard let lyrics = currentLyricsNeedingPersist else { return nil }
        return LyricsPersister.saveToDisk(lyrics, to: persistenceSettings.storageDirectory())
    }

    private var currentLyricsNeedingPersist: Lyrics? {
        guard let lyrics = currentLyrics,
              lyrics.metadata.needsPersist,
              lyrics.metadata.persistenceAllowed else { return nil }
        return lyrics
    }

    /// Embedded lyrics and automatic interim picks have no file, and never get one.
    var canRevealCurrentLyricsInFinder: Bool {
        guard let metadata = currentLyrics?.metadata else { return false }
        return metadata.localURL != nil || (metadata.needsPersist && metadata.persistenceAllowed)
    }

    /// Persist (if dirty) and reveal the current lyrics file in Finder. Returns
    /// silently if there is no current lyrics or it has no resolvable URL after
    /// the write attempt.
    func revealCurrentLyricsInFinder() {
        let save = persistCurrentLyricsIfNeeded()
        let lyrics = currentLyrics
        Task {
            await save?.value
            guard let url = lyrics?.metadata.localURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Last-chance flush before the app exits. Called from
    /// `AppDelegate.applicationWillTerminate` so the terminate path doesn't
    /// have to know about the `needsPersist` flag. Blocks until every save is on disk.
    func prepareForTermination() {
        LyricsPersister.saveToDiskNow(currentLyricsNeedingPersist, to: persistenceSettings.storageDirectory())
    }

    // MARK: - Commands

    /// Adopt `lyrics`, picked by the user, as the active selection. When
    /// `writeToiTunesIfAuto` is true and the user has the auto-export preference
    /// enabled, push the lyrics into Apple Music as a side effect (overwriting
    /// existing track lyrics).
    ///
    /// A manual pick overrides an earlier rejection, so the track and its album are
    /// searched again from now on. Late automatic events arriving after this call
    /// are dropped, so automatic finalization/export can never replace the pick.
    func select(_ lyrics: Lyrics, writeToiTunesIfAuto: Bool = false, supporting: [Lyrics] = []) {
        invalidateAutomaticSearch()
        let track = player.currentTrack
        // The lyrics picked here replace the blocked state; nothing to search again for.
        searchStoppedByBlock = false
        if let track {
            blocklist.unblock(track)
        }
        adopt(lyrics, for: track, persist: true)
        // Retain the manual search's other same-song results as restoration
        // evidence for the chosen lyrics.
        supportingLyrics = SupportingLyrics.bounded(supporting, excluding: lyrics)
        if writeToiTunesIfAuto, exportSettings.writeToiTunesAutomatically {
            writeToiTunes()
        }
    }

    enum RejectionScope {
        case track
        case album
    }

    /// "Wrong lyrics" / "Don't search this album": stop searching for the current track
    /// or its whole album, and drop the lyrics shown. The file Lirico saved is deleted and,
    /// with auto-export on, Apple Music's lyrics field is cleared, so the rejection sticks
    /// across restarts.
    func rejectCurrentLyrics(blocking scope: RejectionScope) {
        guard let track = player.currentTrack else { return }
        switch scope {
        case .track:
            blocklist.block(track: track)
        case .album:
            guard let album = track.album else { return }
            blocklist.block(album: album)
        }
        invalidateAutomaticSearch()
        if exportSettings.writeToiTunesAutomatically, canWriteToAppleMusic(track) {
            LyricsPersister.clearAppleMusicLyrics(of: track)
        }
        // Only files Lirico saved itself: a `.lrc` beside the audio file is the
        // user's own, and this app is unsandboxed, so deleting it would be permanent.
        // A save may still be queued, with `localURL` not set yet. Lyrics that may not be
        // persisted were never saved, and that path can hold an earlier save worth keeping.
        if let lyrics = currentLyrics {
            let directory = persistenceSettings.storageDirectory()
            let queued = lyrics.metadata.persistenceAllowed ? LyricsPersister.fileURL(for: lyrics, in: directory) : nil
            let saved = [lyrics.metadata.localURL, queued]
            for url in Set(saved.compactMap { $0 }) where persistenceSettings.storageDirectoryContains(url) {
                LyricsPersister.deleteFromDisk(url)
            }
        }
        currentLyrics = nil
        supportingLyrics = []
        status = .blocked(scope)
        searchStoppedByBlock = true
    }

    /// Settings can lift the block on the song that's playing; search for it now rather
    /// than leaving it blocked until the next track change.
    private func searchAgainIfUnblocked() {
        guard searchStoppedByBlock, let track = player.currentTrack, !blocklist.isBlocked(track: track) else { return }
        if let album = track.album, blocklist.isBlocked(album: album) { return }
        currentTrackChanged(to: track)
    }

    private func currentTrackChanged(to track: MusicTrack?) {
        persistCurrentLyricsIfNeeded()
        currentLyrics = nil
        supportingLyrics = []
        invalidateAutomaticSearch()
        automaticSearchTrack = track
        searchStoppedByBlock = false

        guard let track else {
            // Until the permission check answers; a known denial stays up rather than flickering.
            if case .automationDenied = status {} else {
                status = .noTrack
            }
            updateNoTrackStatus()
            return
        }
        let title = track.title ?? ""
        let artist = track.artist ?? ""

        guard !blocklist.isBlocked(track: track) else {
            status = .blocked(.track)
            searchStoppedByBlock = true
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
        if let album = track.album, blocklist.isBlocked(album: album) {
            status = currentLyrics == nil ? .blocked(.album) : .loaded
            searchStoppedByBlock = true
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
        let candidates = AutomationPermission.runningCandidates(designatedBundleID: player.designatedPlayerBundleID)
        Task { [weak self] in
            let denied = await Task.detached(priority: .userInitiated) {
                AutomationPermission.deniedPlayerName(among: candidates)
            }.value
            // A track that arrived meanwhile owns the status now.
            guard let self, self.player.currentTrack == nil else { return }
            let newStatus: LyricsStatus = denied.map { .automationDenied(playerName: $0) } ?? .noTrack
            if self.status != newStatus {
                self.status = newStatus
            }
        }
    }

    // MARK: - Applying automatic search decisions

    /// Stops the running automatic search and makes any of its events still in flight
    /// no-ops, so a late result can't replace what the user picked, cleared or imported.
    private func invalidateAutomaticSearch() {
        automaticSearchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
    }

    /// Puts `lyrics` on screen, labelled with `track`. Only lyrics allowed to `persist` are
    /// ever saved or exported; automatic interim picks aren't.
    private func adopt(_ lyrics: Lyrics, for track: MusicTrack?, persist: Bool) {
        if let track {
            lyrics.associateWithTrack(track)
        }
        if persist {
            lyrics.metadata.persistenceAllowed = true
        }
        // Usually already on screen as the interim pick; assigning it again resets
        // the line index and makes the karaoke line blink.
        if lyrics !== currentLyrics {
            currentLyrics = lyrics
        }
        status = .loaded
    }

    private func isCurrentAutomaticSearch(_ generation: Int) -> Bool {
        automaticSearchGeneration == generation && player.currentTrack?.id == automaticSearchTrack?.id
    }

    private func apply(_ decision: AutomaticLyricsSearch.Decision, initialLyrics: Lyrics?) {
        switch decision {
        // Bind results to the searched track, not the live one, so a change that lands after
        // the currency check can't label, save or export this song's lyrics under the next.
        case .interim(let lyrics):
            adopt(lyrics, for: automaticSearchTrack, persist: false)

        case .supporting(let supporting):
            updateSupportingLyrics(supporting)

        case .finished(let accepted, let supporting):
            if let accepted {
                adopt(accepted, for: automaticSearchTrack, persist: true)
            }
            updateSupportingLyrics(supporting)
            status = currentLyrics == nil ? .notFound : .loaded
            persistCurrentLyricsIfNeeded()
            // Kept local lyrics are already what the user has; re-exporting them would
            // cost an Apple Event per track and clobber Apple Music's field for nothing.
            if exportSettings.writeToiTunesAutomatically, currentLyrics !== initialLyrics,
               let track = automaticSearchTrack {
                writeToiTunes(to: track)
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
        // Only after validation, so a bad import leaves the running search alone.
        invalidateAutomaticSearch()

        preparation.prepare(lrc)
        lrc.metadata.needsPersist = true
        searchStoppedByBlock = false
        blocklist.unblock(track)
        adopt(lrc, for: track, persist: true)
        supportingLyrics = []
    }
}
