import AppKit
import Combine
import MusicPlayer
import LyricsXFoundation

// MARK: - AutomaticAcceptancePolicy

/// Governs which remote candidates are eligible to replace the current lyrics
/// during an automatic search.
///
/// `.normal`: any strong remote candidate may become `currentLyrics`.
/// `.localUpgradeOnly`: only materially-better strong remote candidates may
///  replace the already-displayed local line-synced lyrics. Evaluated local
///  score is computed once at search start and retained for comparisons.
enum AutomaticAcceptancePolicy {
    case normal
    /// An exact/strong remote candidate may replace local line-synced lyrics only
    /// when it is materially better (karaoke within window, or line-synced +5 points).
    case localUpgradeOnly(existing: Lyrics, existingEvaluation: LyricsCandidateEvaluation)
}

// MARK: - LyricsSession

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

    /// Immutable, main-actor-captured snapshot of the current lyrics' display
    /// metadata, consumed by `LyricsDisplayCoordinator` instead of the live struct.
    @Published private(set) var displayMetadata: LyricsDisplayMetadata = .empty

    /// Other same-song candidates kept as evidence for display-time explicit-word
    /// restoration. This is request-dependent display state, not persisted lyrics
    /// metadata, and is bounded to keep memory predictable. Written only by the
    /// session (automatic search collection, manual select); reset on track change.
    @Published private(set) var supportingLyrics: [Lyrics] = []

    /// Upper bound on retained supporting candidates. A handful is plenty for
    /// cross-candidate consensus; more would only add memory and noise.
    private let maxSupportingLyrics = 10

    private var searchRequest: LyricsSearchRequest?
    private var searchTask: Task<Void, Never>?

    /// Monotonically-increasing counter. Incremented on every track change,
    /// manual select, and manual clear. Any automatic event that arrives with a
    /// stale generation number is silently dropped, closing the correctness gap
    /// (DEC-007) where late async events could overwrite a user selection.
    private var automaticSearchGeneration: Int = 0

    private var cancelBag = Set<AnyCancellable>()

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
        explicitResolver: ExplicitLyricsResolving = ExplicitLyricsResolver(),
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
        player.currentTrackWillChange
            .signal()
            .sink { [weak self] in
                Task { @MainActor in
                    self?.currentTrackChanged()
                }
            }
            .store(in: &cancelBag)

        clock.dedupTarget = { [weak self] in self?.currentLineIndex }
        clock.currentLineIndex
            // Mirror onto the main thread before driving UI. The clock emits on
            // its background queue; assigning the @Published property there let
            // the coordinator-backed surfaces (karaoke, menu bar) and the
            // main-thread surfaces (sync panel, HUD) repaint in nondeterministic
            // order, so at a line boundary one could briefly lead the other by a
            // whole line. A single main-thread origin keeps every surface in step.
            .receive(on: DispatchQueue.main)
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
            Task { @MainActor in
                self?.currentTrackChanged()
            }
        }
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
        // Retain the manual search's other same-song results as restoration
        // evidence for the chosen lyrics.
        supportingLyrics = boundedSupporting(supporting, excluding: lyrics)
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
            if let url = currentLyrics?.metadata.localURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        currentLyrics = nil
        supportingLyrics = []
    }

    @MainActor
    func currentTrackChanged() {
        persistCurrentLyricsIfNeeded()
        currentLyrics = nil
        currentLineIndex = nil
        supportingLyrics = []

        // Invalidate the previous search so late events from the old track are
        // no-ops even if they arrive after the new task starts.
        automaticSearchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil

        guard let track = player.currentTrack else {
            return
        }
        // FIXME: deal with optional value
        let title = track.title ?? ""
        let artist = track.artist ?? ""

        guard !SearchBlocklist.isBlocked(track: track) else {
            return
        }

        // Determine the acceptance policy from local lyrics.
        let acceptancePolicy: AutomaticAcceptancePolicy
        switch LocalLyricsLoader.load(
            track: track,
            title: title,
            artist: artist,
            preparation: preparation,
            settings: persistenceSettings
        ) {
        case .found(let lyrics):
            currentLyrics = lyrics
            if lyrics.isKaraokeTimed {
                // Local karaoke is the best we can get — no network search.
                return
            }
            // Local line-synced: display immediately but search for a clearly better remote.
            let localEval = evaluateLocalLyrics(
                lyrics: lyrics,
                title: title,
                artist: artist,
                duration: track.duration,
                album: track.album
            )
            acceptancePolicy = .localUpgradeOnly(existing: lyrics, existingEvaluation: localEval)

        case .foundPartial(let lyrics):
            currentLyrics = lyrics
            // Partial (.lrc) local lyrics: show immediately, continue normal search.
            acceptancePolicy = .normal

        case .none:
            acceptancePolicy = .normal
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

        let requestedDuration: TimeInterval? = track.duration
        let requestedAlbum: String? = track.album
        let mode: LyricsSearchMode = .titleAndArtist(title: title, artist: artist)
        let configuration = searchSettings.rankingConfiguration

        // Capture the current generation before launching. The task checks this
        // token at every candidate/finalization point to reject stale results.
        let generation = automaticSearchGeneration

        searchTask = Task { @MainActor in
            await runAutomaticSearch(
                request: request,
                mode: mode,
                requestedDuration: requestedDuration,
                requestedAlbum: requestedAlbum,
                acceptancePolicy: acceptancePolicy,
                configuration: configuration,
                generation: generation
            )
        }
    }

    // MARK: - Automatic search state machine

    /// Runs the automatic search loop with a 15-second deadline.
    ///
    /// Candidates are collected as `.candidate` events arrive. The first strong
    /// acceptable candidate is shown as an interim `currentLyrics` immediately.
    /// Subsequent candidates are re-ranked via `LyricsCandidateRanker.bestCandidate`
    /// and replace `currentLyrics` whenever a better one is found.
    ///
    /// Finalization (persist + export) happens EXACTLY ONCE: either when the
    /// provider stream emits `.completed` or when the 15-second deadline fires,
    /// whichever comes first. Stale events (generation mismatch) are always ignored.
    @MainActor
    private func runAutomaticSearch(
        request: LyricsSearchRequest,
        mode: LyricsSearchMode,
        requestedDuration: TimeInterval?,
        requestedAlbum: String?,
        acceptancePolicy: AutomaticAcceptancePolicy,
        configuration: LyricsCandidateRankingConfiguration,
        generation: Int
    ) async {
        let stream = pipeline.events(
            for: request,
            mode: mode,
            requestedDuration: requestedDuration,
            requestedAlbum: requestedAlbum
        )

        // State shared between the two racing tasks (both @MainActor, so safe).
        // Both tasks execute on the main actor; mutable sharing is safe.
        var collectedCandidates: [EvaluatedLyricsCandidate] = []

        // Race: event-stream consumer vs. 15-second deadline.
        // Each child task returns a Bool: true = stream finished/ran to end, false = deadline fired.
        // The parent finalizes once after the first child completes, then cancels the other.
        await withTaskGroup(of: Bool.self) { group in
            // Consumer task: iterates the event stream until .completed or cancellation.
            // Returns true when the stream is exhausted (naturally or via .completed event).
            group.addTask { @MainActor in
                for await event in stream {
                    // Stale generation: the track changed or user acted — stop now.
                    guard self.automaticSearchGeneration == generation else { break }

                    switch event {
                    case .candidate(let candidate):
                        collectedCandidates.append(candidate)

                        // Show the first strong acceptable candidate immediately
                        // (interim display, no persist/export yet).
                        self.maybeUpdateInterim(
                            with: candidate,
                            collected: collectedCandidates,
                            policy: acceptancePolicy,
                            mode: mode,
                            configuration: configuration,
                            generation: generation
                        )

                    case .completed:
                        // Stream signalled all providers finished normally; the
                        // race exits naturally when this task returns.
                        break

                    case .providerStarted, .providerFinished, .providerFailed:
                        // Automatic search ignores provider-status events.
                        break
                    }
                }
                return true
            }

            // Deadline task: fires after 15 seconds.
            // Returns false to signal that the deadline beat the stream.
            group.addTask { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                } catch {
                    // Cancelled before 15 s — the consumer finished first.
                    return false
                }
                return false
            }

            // Wait for the first child to finish, then cancel the other (DEC-003).
            _ = await group.next()
            group.cancelAll()
        }

        // Finalize EXACTLY ONCE here, after the race resolves.
        // Generation check prevents stale finalization when track changed / user acted.
        guard automaticSearchGeneration == generation else { return }

        finalizeAutomaticSearch(
            collectedCandidates: collectedCandidates,
            mode: mode,
            acceptancePolicy: acceptancePolicy,
            configuration: configuration,
            generation: generation
        )
    }

    /// Performs finalization: picks the best candidate, updates `currentLyrics`,
    /// persists dirty lyrics, and auto-exports to Apple Music if enabled.
    ///
    /// Called exactly once per automatic search, from `runAutomaticSearch` after
    /// the race between stream completion and the 15-second deadline resolves.
    @MainActor
    private func finalizeAutomaticSearch(
        collectedCandidates: [EvaluatedLyricsCandidate],
        mode: LyricsSearchMode,
        acceptancePolicy: AutomaticAcceptancePolicy,
        configuration: LyricsCandidateRankingConfiguration,
        generation: Int
    ) {
        // Generation guard: manual select/clear/track-change happened after the
        // search started — do not overwrite the user's choice.
        guard automaticSearchGeneration == generation else { return }

        let ranker = LyricsCandidateRanker()
        if let bestCandidate = ranker.bestCandidate(
            from: collectedCandidates,
            mode: mode,
            configuration: configuration
        ) {
            let approved = shouldAccept(
                candidate: bestCandidate,
                policy: acceptancePolicy,
                configuration: configuration,
                generation: generation
            )
            if approved {
                // Re-check generation after shouldAccept (it's synchronous, but
                // be defensive about future changes).
                guard automaticSearchGeneration == generation else { return }
                if let track = player.currentTrack {
                    bestCandidate.lyrics.associateWithTrack(track)
                }
                bestCandidate.lyrics.metadata.persistenceAllowed = true
                currentLyrics = bestCandidate.lyrics
            }
        }

        // Final restoration evidence: the other same-song candidates for whatever
        // lyrics ended up displayed (the new pick, or retained local lyrics).
        supportingLyrics = boundedSupporting(from: collectedCandidates, selected: currentLyrics)

        // Persist and export after finalization — never on interim updates.
        persistCurrentLyricsIfNeeded()
        if exportSettings.writeToiTunesAutomatically {
            writeToiTunes(overwrite: true)
        }
    }

    /// Updates `currentLyrics` with an interim result when the candidate is
    /// better than the current best. Interim results are display-only — no
    /// persist or export is triggered here.
    ///
    /// The ranker is used to pick the best candidate from everything collected
    /// so far, ensuring karaoke preference and source priority are respected from
    /// the start rather than only at finalization.
    private func maybeUpdateInterim(
        with newCandidate: EvaluatedLyricsCandidate,
        collected: [EvaluatedLyricsCandidate],
        policy: AutomaticAcceptancePolicy,
        mode: LyricsSearchMode,
        configuration: LyricsCandidateRankingConfiguration,
        generation: Int
    ) {
        guard automaticSearchGeneration == generation else { return }

        let ranker = LyricsCandidateRanker()
        guard let best = ranker.bestCandidate(
            from: collected,
            mode: mode,
            configuration: configuration
        ) else { return }

        // Never display rejected or unlikely via automatic search.
        guard best.evaluation.visibility == .normal
            || best.evaluation.visibility == .looseFallback
        else { return }

        // Apply acceptance policy — if local upgrade only, check upgrade eligibility.
        guard shouldAccept(
            candidate: best,
            policy: policy,
            configuration: configuration,
            generation: generation
        ) else { return }

        // Refresh restoration evidence as the collection grows, even when the
        // displayed candidate itself is unchanged.
        supportingLyrics = boundedSupporting(from: collected, selected: best.lyrics)

        // Only update if this candidate is actually different from what's displayed.
        guard currentLyrics !== best.lyrics else { return }

        if let track = player.currentTrack {
            best.lyrics.associateWithTrack(track)
        }
        // Interim: update display but do NOT set needsPersist / export.
        currentLyrics = best.lyrics
    }

    /// Returns whether `candidate` is acceptable given the current policy.
    ///
    /// For `.normal` policy: any `.normal` or eligible `.looseFallback` candidate
    /// is accepted. For `.localUpgradeOnly`: delegates to the pure package-level
    /// `shouldRemoteUpgradeLocal(candidate:local:configuration:)` function
    /// (see `LyricsLocalUpgradePolicy.swift`). The upstream karaoke-local
    /// short-circuit (isKaraokeTimed early-return) stays in `currentTrackChanged`.
    private func shouldAccept(
        candidate: EvaluatedLyricsCandidate,
        policy: AutomaticAcceptancePolicy,
        configuration: LyricsCandidateRankingConfiguration,
        generation: Int
    ) -> Bool {
        switch policy {
        case .normal:
            // Any normal candidate is fine; loose-fallback is gated by the
            // threshold enforced in `bestCandidate` already (score ≥ 80).
            return candidate.evaluation.visibility == .normal
                || candidate.evaluation.visibility == .looseFallback

        case .localUpgradeOnly(_, let localEval):
            // Delegate to the pure package-level function (LyricsLocalUpgradePolicy).
            // The upstream karaoke-local short-circuit (isKaraokeTimed early-return in
            // currentTrackChanged) is kept in LyricsSession; this path only governs
            // the line-synced-local case.
            return shouldRemoteUpgradeLocal(
                candidate: candidate.evaluation,
                local: localEval,
                configuration: configuration
            )
        }
    }

    // MARK: - Supporting candidate retention

    /// Same-song alternates (normal visibility only — never loose fallback or
    /// wrong-song candidates) from a completed collection, excluding the
    /// displayed lyrics, bounded.
    private func boundedSupporting(
        from collected: [EvaluatedLyricsCandidate],
        selected: Lyrics?
    ) -> [Lyrics] {
        let sameSong = collected
            .filter { $0.evaluation.visibility == .normal }
            .map(\.lyrics)
        return boundedSupporting(sameSong, excluding: selected)
    }

    private func boundedSupporting(_ lyrics: [Lyrics], excluding selected: Lyrics?) -> [Lyrics] {
        var result: [Lyrics] = []
        for item in lyrics {
            if let selected, item === selected { continue }
            if result.contains(where: { $0 === item }) { continue }
            result.append(item)
            if result.count >= maxSupportingLyrics { break }
        }
        return result
    }

    // MARK: - Local lyrics evaluation

    /// Evaluates local lyrics with a synthetic source name stamped into
    /// `metadata.service` for diagnostics. The synthetic name is NOT a remote
    /// source-priority entry and does not participate in source-priority ranking.
    ///
    /// Source name convention:
    ///   - Embedded track lyrics → "Embedded"
    ///   - Beside-track `.lrcx` / `.lrc` → "Beside Track"
    ///   - Saved-path `.lrcx` / `.lrc` in storage directory → "Local Storage"
    private func evaluateLocalLyrics(
        lyrics: Lyrics,
        title: String,
        artist: String,
        duration: TimeInterval?,
        album: String?
    ) -> LyricsCandidateEvaluation {
        // Stamp a synthetic source name so the evaluation includes a meaningful
        // service field in diagnostics/logging without polluting remote source lists.
        let syntheticSource = syntheticLocalSourceName(for: lyrics)
        lyrics.metadata.service = syntheticSource

        let evaluator = LyricsCandidateEvaluator()
        return evaluator.evaluate(
            lyrics: lyrics,
            mode: .titleAndArtist(title: title, artist: artist),
            requestedDuration: duration,
            requestedAlbum: album
        )
    }

    /// Returns the synthetic canonical source name for a local lyrics object,
    /// based on where the file came from (detected from metadata).
    ///
    /// Detection rules (in priority order):
    ///   1. No `localURL` → embedded (came from track.lyrics string).
    ///   2. `localURL` is beside the track file (same base name, different extension) → "Beside Track".
    ///   3. Otherwise → "Local Storage" (saved-path storage directory).
    private func syntheticLocalSourceName(for lyrics: Lyrics) -> String {
        guard let localURL = lyrics.metadata.localURL else {
            return "Embedded"
        }
        // Beside-track files share a base name with the track audio file and have a
        // `.lrcx` or `.lrc` extension. There is no direct track URL available here,
        // but beside-track URLs are normally NOT inside the app's configured storage
        // directory. Use "Beside Track" for any local URL, "Local Storage" only when
        // the URL is inside the persistence storage directory.
        let storageDir = persistenceSettings.storageDirectory().url
        if localURL.path.hasPrefix(storageDir.path) {
            return "Local Storage"
        }
        return "Beside Track"
    }
}

extension LyricsSession {
    func importLyrics(_ lyricsString: String) throws {
        // Cancel any in-flight automatic search so it cannot overwrite the
        // user's import — mirrors the same contract as select() and clear().
        automaticSearchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil

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
        lrc.metadata.persistenceAllowed = true
        currentLyrics = lrc
        supportingLyrics = []
        SearchBlocklist.unblock(track: track)
        SearchBlocklist.unblock(album: track.album ?? "")
    }
}
