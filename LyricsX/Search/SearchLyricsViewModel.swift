import AppKit
import Combine
@preconcurrency import LyricsKit
import LyricsXFoundation
import MusicPlayer

// MARK: - SearchStatus

/// One source of truth for what the Search Lyrics window status line shows.
///
/// `searching` and `foundVisible` are both derived from the same in-flight flag
/// + evaluated candidate set, ensuring the button label and status text stay in
/// sync without duplicating logic.
enum SearchStatus: Equatable {
    /// No search has been started yet (or was cleared by Search Again).
    case idle
    /// A search is currently in flight; `summary` is the latest provider event description.
    case searching(summary: String)
    /// Search completed or is in progress and at least one visible (likely/loose) row exists.
    case foundVisible(count: Int, hiddenUnlikely: Int, rejected: Int)
    /// Search completed with zero visible rows (normal or loose-fallback), but some may be hidden.
    case noMatches(hiddenUnlikely: Int, rejected: Int)
    /// At least one provider failed; some partial results may still be shown.
    case failed(message: String, visibleCount: Int, hiddenUnlikely: Int, rejected: Int)
    /// The 30 s manual timeout elapsed; partial results remain visible.
    case timedOut(visibleCount: Int, hiddenUnlikely: Int, rejected: Int)
    /// The user cancelled the active search; partial results remain visible.
    case cancelled(visibleCount: Int, hiddenUnlikely: Int, rejected: Int)
}

// MARK: - SearchButtonLabel

/// The label the Search/Cancel/Search Again button shows.
///
/// Derived entirely from `isSearching` + `fieldsChangedSinceActiveSearch`, so
/// it is impossible for the label and the action to diverge.
enum SearchButtonLabel {
    case search
    case cancel
    case searchAgain
}

// MARK: - SearchLyricsViewModel

/// View-model for the Search Lyrics window.
///
/// All evaluated candidates are stored; visible rows are derived on demand by the
/// ranker. This guarantees no illegal state where a hidden row could be selected,
/// previewed, or applied.
@MainActor
final class SearchLyricsViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var artist: String = ""

    /// All evaluated candidates collected from the current event stream.
    @Published private(set) var allCandidates: [EvaluatedLyricsCandidate] = []

    /// Current selection by row identity. Always references a currently-visible row;
    /// invalidated whenever the visible set changes in a way that would hide it.
    @Published var selectionID: LyricsResult.ID?

    @Published private(set) var preview: String = ""
    @Published private(set) var artwork: NSImage?

    /// Whether the "Show unlikely results" toggle is on.
    @Published var showUnlikelyResults: Bool = false

    /// Current search status — drives status line copy and button label.
    @Published private(set) var searchStatus: SearchStatus = .idle

    // MARK: - Derived state

    var canSearch: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            || !artist.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var hasTrack: Bool { player.currentTrack != nil }

    /// Apply is enabled only when a visible row is selected AND a track is playing.
    var canApply: Bool {
        guard hasTrack, let id = selectionID else { return false }
        return visibleRows.contains(where: { $0.id == id })
    }

    /// Whether a search is currently in flight.
    var isSearching: Bool {
        if case .searching = searchStatus { return true }
        return false
    }

    /// The button label derived from search state and field-change flag.
    var buttonLabel: SearchButtonLabel {
        guard isSearching else { return .search }
        return fieldsChangedSinceSearch ? .searchAgain : .cancel
    }

    // MARK: - Result partitioning

    /// Full ranked output from `LyricsCandidateRanker`. Cached here so that
    /// `likelyRows`, `unlikelyRows`, and `visibleRows` all share one ranker pass
    /// per render cycle instead of re-running it separately.
    private var rankedCandidates: [EvaluatedLyricsCandidate] {
        LyricsCandidateRanker().rankedCandidates(
            allCandidates,
            mode: currentSearchMode ?? .titleOnly(title: ""),
            configuration: searchSettings.rankingConfiguration
        )
    }

    /// Likely rows: normal + loose-fallback (loose only when no normals exist).
    /// Produced by the ranker, which handles all ordering rules.
    var likelyRows: [LyricsResult] {
        // rankedCandidates returns [likelyOrLoose..., unlikely...].
        // Extract only the non-unlikely portion for the "likely" section.
        rankedCandidates
            .filter { $0.evaluation.visibility != .unlikely }
            .map { LyricsResult(candidate: $0, isUnlikely: false) }
    }

    /// Unlikely rows: candidates with visibility == .unlikely, ordered consistently.
    var unlikelyRows: [LyricsResult] {
        rankedCandidates
            .filter { $0.evaluation.visibility == .unlikely }
            .map { LyricsResult(candidate: $0, isUnlikely: true) }
    }

    /// All rows currently visible in the table: likely rows + (unlikely rows when toggle is on).
    var visibleRows: [LyricsResult] {
        showUnlikelyResults ? likelyRows + unlikelyRows : likelyRows
    }

    /// Count of hidden unlikely candidates (for toggle label copy).
    var unlikelyCount: Int {
        allCandidates.filter { $0.evaluation.visibility == .unlikely }.count
    }

    /// Count of rejected candidates (diagnostic/status accounting only; never shown to user).
    var rejectedCount: Int {
        allCandidates.filter { $0.evaluation.visibility == .rejected }.count
    }

    // MARK: - Internals

    private let player: PlayerHandle
    private let session: LyricsSession
    private let pipeline: LyricsSearchPipeline
    private let searchSettings: SearchSettings

    /// The mode that was active when the current search was launched.
    private var currentSearchMode: LyricsSearchMode?
    /// True when the user has edited title/artist since the current search started.
    private var fieldsChangedSinceSearch: Bool = false
    /// Snapshot of fields at search launch for change-detection.
    private var searchedTitle: String = ""
    private var searchedArtist: String = ""

    /// Monotonically increasing identity for the active manual search.
    private var searchGeneration: Int = 0

    private var searchTask: Task<Void, Never>?
    private var fieldCancellable: AnyCancellable?
    private let imageCache = NSCache<NSURL, NSImage>()

    init(
        player: PlayerHandle,
        session: LyricsSession,
        pipeline: LyricsSearchPipeline,
        searchSettings: SearchSettings
    ) {
        self.player = player
        self.session = session
        self.pipeline = pipeline
        self.searchSettings = searchSettings

        // Watch field edits to set fieldsChangedSinceSearch while a search is active.
        fieldCancellable = Publishers.CombineLatest($title, $artist)
            .dropFirst()
            .sink { [weak self] newTitle, newArtist in
                guard let self, self.isSearching else { return }
                self.fieldsChangedSinceSearch = self.trimmedFieldValue(newTitle) != self.searchedTitle
                    || self.trimmedFieldValue(newArtist) != self.searchedArtist
                // Changing fields does NOT clear partial results — Search Again does that.
            }
    }

    private func trimmedFieldValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Public API

    /// Refresh title/artist from the current track and re-run the search when they changed.
    /// Called by the window controller on every `showWindow(_:)`.
    func reloadFromCurrentTrack() {
        guard let track = player.currentTrack else {
            // No track: clear everything but leave the search available for manual lookup.
            searchGeneration &+= 1
            searchTask?.cancel()
            searchTask = nil
            allCandidates = []
            selectionID = nil
            preview = ""
            artwork = nil
            title = ""
            artist = ""
            currentSearchMode = nil
            fieldsChangedSinceSearch = false
            showUnlikelyResults = false
            searchStatus = .idle
            return
        }
        let trackArtist = track.artist ?? ""
        let trackTitle = track.title ?? ""
        if (artist, title) != (trackArtist, trackTitle) {
            artist = trackArtist
            title = trackTitle
            search()
        }
    }

    /// Start a new search with the current field values.
    ///
    /// Cancels any active search, clears old results/selection/preview/artwork, resets
    /// the unlikely toggle, and launches a new event-stream task with a 30 s timeout.
    func search() {
        guard canSearch else { return }

        // Cancel any in-flight search before clearing state.
        searchTask?.cancel()

        let trimmedTitle = trimmedFieldValue(title)
        let trimmedArtist = trimmedFieldValue(artist)

        // Derive the search mode and request from the trimmed fields.
        let mode: LyricsSearchMode
        let searchTerm: LyricsSearchRequest.SearchTerm
        if !trimmedTitle.isEmpty, !trimmedArtist.isEmpty {
            mode = .titleAndArtist(title: trimmedTitle, artist: trimmedArtist)
            searchTerm = .info(title: trimmedTitle, artist: trimmedArtist)
        } else if !trimmedTitle.isEmpty {
            mode = .titleOnly(title: trimmedTitle)
            searchTerm = .keyword(trimmedTitle)
        } else {
            mode = .artistOnly(artist: trimmedArtist)
            searchTerm = .keyword(trimmedArtist)
        }

        // Duration: pass the track value for evaluator scoring; use 0 for the
        // LyricsSearchRequest when no track (LyricsKit requires a concrete TimeInterval).
        let trackDuration = player.currentTrack?.duration
        let requestDuration: TimeInterval = trackDuration ?? 0

        let request = LyricsSearchRequest(
            searchTerm: searchTerm,
            duration: requestDuration,
            limit: 8
        )

        // Persist the mode for result partitioning during the search.
        currentSearchMode = mode
        searchGeneration &+= 1

        // Reset all result/selection/toggle state for the new search.
        allCandidates = []
        selectionID = nil
        preview = ""
        artwork = nil
        showUnlikelyResults = false
        fieldsChangedSinceSearch = false
        searchedTitle = trimmedTitle
        searchedArtist = trimmedArtist
        searchStatus = .searching(summary: "Searching…")

        // Snapshot values for use inside the Task (avoids captures of self fields that
        // could change mid-search).
        let requestedDuration: TimeInterval? = trackDuration
        let requestedAlbum: String? = nil   // Manual search never passes album (plan §Manual search behavior)
        let generation = searchGeneration

        searchTask = Task { @MainActor in
            await runSearch(
                request: request,
                mode: mode,
                requestedDuration: requestedDuration,
                requestedAlbum: requestedAlbum,
                generation: generation
            )
        }
    }

    /// Cancel the current in-flight search. Partial results remain visible.
    func cancelSearch() {
        guard isSearching else { return }
        searchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        let visible = visibleRows.count
        searchStatus = .cancelled(
            visibleCount: visible,
            hiddenUnlikely: unlikelyCount,
            rejected: rejectedCount
        )
    }

    /// The action behind the Search / Cancel / Search Again button.
    func performButtonAction() {
        switch buttonLabel {
        case .search:
            search()
        case .cancel:
            cancelSearch()
        case .searchAgain:
            search()
        }
    }

    /// Apply the currently selected visible row to the session.
    func apply() {
        guard let id = selectionID,
              let result = visibleRows.first(where: { $0.id == id }),
              player.currentTrack != nil
        else { return }
        if let track = player.currentTrack {
            SearchBlocklist.unblock(track: track)
            SearchBlocklist.unblock(album: track.album ?? "")
        }
        session.select(result.lyrics, writeToiTunesIfAuto: true)
    }

    /// Recompute preview text and artwork for the current selection.
    /// The view calls this when `selectionID` changes.
    func updatePreview() {
        guard let id = selectionID,
              let result = visibleRows.first(where: { $0.id == id })
        else {
            preview = ""
            artwork = nil
            return
        }
        preview = result.lyrics.description
        loadArtwork(for: result.lyrics)
    }

    func lrcText(for result: LyricsResult) -> String {
        result.lyrics.description
    }

    // MARK: - Event stream consumer

    private func runSearch(
        request: LyricsSearchRequest,
        mode: LyricsSearchMode,
        requestedDuration: TimeInterval?,
        requestedAlbum: String?,
        generation: Int
    ) async {
        // Race the event-stream consumer against a 30 s timeout.
        // Using TaskGroup: the first child to finish cancels the other.
        // The timeout child sets the .timedOut status before finishing; the
        // consumer child then exits the for-await loop on cancellation.
        // The consumer NEVER sets status when it exits due to cancellation —
        // it guards on `isSearching` which is false after the timeout fires.
        await withTaskGroup(of: Bool.self) { group in
            // Bool result: true = stream completed/consumed, false = timeout fired
            group.addTask { @MainActor in
                await self.consumeEventStream(
                    request: request,
                    mode: mode,
                    requestedDuration: requestedDuration,
                    requestedAlbum: requestedAlbum,
                    generation: generation
                )
                return true
            }

            // Timeout sentinel: sleeps 30 s then marks status as timedOut.
            // It finishes with false to signal that it won the race.
            group.addTask { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                } catch {
                    // Cancelled before 30 s — stream finished first.
                    return false
                }
                // Only apply timeout if we are still the active search.
                guard self.searchGeneration == generation, self.isSearching else {
                    return false
                }
                let visible = self.visibleRows.count
                self.searchStatus = .timedOut(
                    visibleCount: visible,
                    hiddenUnlikely: self.unlikelyCount,
                    rejected: self.rejectedCount
                )
                return false
            }

            // First child to complete wins; cancel the other.
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func consumeEventStream(
        request: LyricsSearchRequest,
        mode: LyricsSearchMode,
        requestedDuration: TimeInterval?,
        requestedAlbum: String?,
        generation: Int
    ) async {
        let stream = pipeline.events(
            for: request,
            mode: mode,
            requestedDuration: requestedDuration,
            requestedAlbum: requestedAlbum
        )

        var failureMessages: [String] = []
        var completedNormally = false

        for await event in stream {
            // Bail early if a newer search has been launched (task cancel propagates,
            // but guard against any race between the cancel and the next yield).
            guard searchGeneration == generation, isSearching else { break }

            switch event {
            case .providerStarted(let source):
                updateSearchingSummary(for: source)

            case .candidate(let candidate):
                allCandidates.append(candidate)
                invalidateSelectionIfHidden()
                updateFoundStatus()

            case .providerFinished(let source, _):
                updateSearchingSummary(afterFinished: source)

            case .providerFailed(let source, let message, _):
                failureMessages.append("\(source): \(message)")
                updateSearchingSummary(afterFailed: source)

            case .completed:
                completedNormally = true
            }
        }

        // After the stream finishes (normally, cancelled, or timeout-cancelled):
        // Only update status if we are still the active search (i.e. not superseded).
        guard searchGeneration == generation, isSearching else { return }

        let visible = visibleRows.count
        let hidden = unlikelyCount
        let rejected = rejectedCount

        if completedNormally {
            if !failureMessages.isEmpty {
                let msg = failureMessages.joined(separator: " · ")
                searchStatus = .failed(
                    message: msg,
                    visibleCount: visible,
                    hiddenUnlikely: hidden,
                    rejected: rejected
                )
            } else if visible > 0 {
                searchStatus = .foundVisible(count: visible, hiddenUnlikely: hidden, rejected: rejected)
            } else {
                searchStatus = .noMatches(hiddenUnlikely: hidden, rejected: rejected)
            }
        } else {
            // Stream ended without .completed — was cancelled (by user or timeout sentinel).
            // Status was already updated by cancelSearch() or the timeout handler; only
            // update here if we are still showing .searching (e.g. stream returned early
            // without a proper cancel signal).
            if isSearching {
                searchStatus = .cancelled(
                    visibleCount: visible,
                    hiddenUnlikely: hidden,
                    rejected: rejected
                )
            }
        }
    }

    // MARK: - Status helpers

    private func updateSearchingSummary(for source: String) {
        searchStatus = .searching(summary: "Searching \(source)…")
    }

    private func updateSearchingSummary(afterFinished source: String) {
        let visible = visibleRows.count
        let hidden = unlikelyCount
        if visible > 0 {
            let copy = hidden > 0
                ? "\(visible) likely \(visible == 1 ? "match" : "matches") · \(hidden) unlikely hidden"
                : "Found \(visible) likely \(visible == 1 ? "match" : "matches")"
            searchStatus = .searching(summary: copy)
        } else {
            searchStatus = .searching(summary: "Searching…")
        }
    }

    private func updateSearchingSummary(afterFailed source: String) {
        let visible = visibleRows.count
        if visible > 0 {
            searchStatus = .searching(summary: "\(source) failed · showing \(visible) partial \(visible == 1 ? "match" : "matches")")
        } else {
            searchStatus = .searching(summary: "\(source) failed…")
        }
    }

    private func updateFoundStatus() {
        let visible = visibleRows.count
        let hidden = unlikelyCount
        // Keep in .searching so the button still shows Cancel during the stream.
        if case .searching = searchStatus {
            let copy: String
            if visible > 0 {
                copy = hidden > 0
                    ? "\(visible) likely \(visible == 1 ? "match" : "matches") · \(hidden) unlikely hidden"
                    : "Found \(visible) likely \(visible == 1 ? "match" : "matches")"
            } else {
                copy = hidden > 0
                    ? "No likely matches · \(hidden) unlikely hidden"
                    : "Searching…"
            }
            searchStatus = .searching(summary: copy)
        }
        // If status is not .searching (e.g. timed out), leave it alone.
    }

    // MARK: - Selection invalidation

    private func clearSelectionPreview() {
        selectionID = nil
        preview = ""
        artwork = nil
    }

    private func invalidateSelectionIfHidden() {
        guard let id = selectionID,
              !visibleRows.contains(where: { $0.id == id })
        else { return }
        clearSelectionPreview()
    }

    /// Called by the view when the unlikely toggle changes.
    /// If the toggle was turned OFF and the selected row is now hidden, clear selection.
    func unlikelyToggleChanged() {
        guard !showUnlikelyResults else { return }
        invalidateSelectionIfHidden()
    }

    // MARK: - Artwork loading

    private func loadArtwork(for lyrics: Lyrics) {
        guard let url = lyrics.metadata.artworkURL else {
            artwork = nil
            return
        }
        if let cached = imageCache.object(forKey: url as NSURL) {
            artwork = cached
            return
        }
        artwork = nil
        fetchArtwork(url: url) { [weak self] image in
            guard let self, let image else { return }
            self.imageCache.setObject(image, forKey: url as NSURL)
            // Guard against a selection change while the fetch was in flight.
            if let id = self.selectionID,
               let selected = self.visibleRows.first(where: { $0.id == id }),
               selected.lyrics.metadata.artworkURL == url {
                self.artwork = image
            }
        }
    }
}

// MARK: - LyricsResult

/// Identifiable wrapper around an `EvaluatedLyricsCandidate` for SwiftUI selection.
///
/// Identity is by `ObjectIdentifier(lyrics)` so selection survives re-ranking
/// after new candidates arrive.
struct LyricsResult: Identifiable, Hashable {
    let lyrics: Lyrics
    let evaluation: LyricsCandidateEvaluation
    let isUnlikely: Bool

    var id: ObjectIdentifier { ObjectIdentifier(lyrics) }

    var title: String { lyrics.idTags[.title] ?? "[lacking]" }
    var artist: String { lyrics.idTags[.artist] ?? "[lacking]" }
    var source: String { lyrics.metadata.service ?? "[lacking]" }

    /// SF Symbol name for the karaoke mic indicator; empty string for line-synced rows.
    var syncIconName: String { evaluation.syncKind == .karaoke ? "mic.fill" : "" }

    init(candidate: EvaluatedLyricsCandidate, isUnlikely: Bool) {
        self.lyrics = candidate.lyrics
        self.evaluation = candidate.evaluation
        self.isUnlikely = isUnlikely
    }

    static func == (lhs: LyricsResult, rhs: LyricsResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
