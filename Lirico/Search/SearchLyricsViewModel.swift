import AppKit
import Combine
@preconcurrency import LyricsKit
import LiricoFoundation
import MusicPlayer

// MARK: - SearchStatus

/// Where the search is. Result counts aren't carried here: they change with the
/// "show unlikely" toggle after the search ends, so the view reads them live.
enum SearchStatus: Equatable {
    case idle
    case searching(summary: String)
    case finished
    case failed(message: String)
    case timedOut
    case cancelled

    static func matchSummary(likely: Int, hiddenUnlikely: Int) -> String {
        let matches = likely > 0 ? "\(likely) likely \(likely == 1 ? "match" : "matches")" : "No likely matches"
        return hiddenUnlikely > 0 ? "\(matches) · \(hiddenUnlikely) unlikely hidden" : matches
    }

    static func partialMatches(_ count: Int) -> String {
        "showing \(count) partial \(count == 1 ? "match" : "matches")"
    }
}

// MARK: - SearchButtonLabel

enum SearchButtonLabel {
    case search
    case cancel
    case searchAgain
}

// MARK: - SearchLyricsViewModel

@MainActor
final class SearchLyricsViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published private(set) var visibleRows: [LyricsResult] = []
    @Published var selectionID: LyricsResult.ID?
    @Published private(set) var preview: String = ""
    @Published private(set) var artwork: NSImage?
    @Published var showUnlikelyResults: Bool = false {
        didSet {
            guard showUnlikelyResults != oldValue else { return }
            rebuildVisibleRows()
        }
    }
    @Published private(set) var searchStatus: SearchStatus = .idle
    @Published private(set) var unlikelyCount: Int = 0

    var likelyCount: Int { visibleRows.count { !$0.isUnlikely } }
    var hiddenUnlikelyCount: Int { showUnlikelyResults ? 0 : unlikelyCount }

    var canSearch: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            || !artist.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var canApply: Bool {
        guard let trackID = player.currentTrack?.id, trackID == searchedTrack?.id,
              let id = selectionID else { return false }
        return visibleRows.contains(where: { $0.id == id })
    }

    var isSearching: Bool {
        if case .searching = searchStatus { return true }
        return false
    }

    var buttonLabel: SearchButtonLabel {
        guard isSearching else { return .search }
        return fieldsChangedSinceSearch ? .searchAgain : .cancel
    }

    private let player: PlayerHandle
    private let session: LyricsSession
    private let pipeline: LyricsSearchPipeline
    private let searchSettings: SearchSettings

    private var results: ManualSearchResults?
    private var pendingCandidates: [EvaluatedLyricsCandidate] = []
    /// The lyrics already loaded for the current track when the window opened,
    /// snapshotted so the "currently loaded" row indicator stays stable while
    /// results stream in. Refreshed when the user applies a different result.
    private var loadedLyrics: Lyrics?
    /// The track these results are for. Applying binds lyrics to whatever is playing,
    /// so once the player moves on, results for the old track must not be applied.
    private var searchedTrack: MusicTrack?
    private var fieldsChangedSinceSearch: Bool = false
    private var searchedTitle: String = ""
    private var searchedArtist: String = ""
    private var searchGeneration: Int = 0
    private var searchTask: Task<Void, Never>?
    private var fieldCancellable: AnyCancellable?
    private let imageCache = NSCache<NSURL, NSImage>()
    private let albumArtworkCache = NSCache<NSString, NSImage>()
    private let candidateFlushBatchSize = 6
    private let candidateFlushIntervalNanoseconds: UInt64 = 75_000_000
    private var lastCandidateFlushUptime: UInt64 = 0

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

        fieldCancellable = Publishers.CombineLatest($title, $artist)
            .dropFirst()
            .sink { [weak self] newTitle, newArtist in
                guard let self, self.isSearching else { return }
                self.fieldsChangedSinceSearch = self.trimmedFieldValue(newTitle) != self.searchedTitle
                    || self.trimmedFieldValue(newArtist) != self.searchedArtist
            }
    }

    private func trimmedFieldValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
    }

    private func currentUptimeNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    /// Takes the track rather than reading `player.currentTrack`: on a track change the
    /// player announces the new track before its property is updated.
    func reload(for track: MusicTrack?) {
        loadedLyrics = session.currentLyrics
        searchedTrack = track
        rebuildVisibleRows()
        guard let track else {
            searchGeneration &+= 1
            searchTask?.cancel()
            searchTask = nil
            resetResults()
            results = nil
            title = ""
            artist = ""
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

    func search() {
        guard let query = LyricsSearchQuery.manual(title: title, artist: artist, duration: searchedTrack?.duration) else {
            return
        }

        searchTask?.cancel()

        searchGeneration &+= 1
        resetResults()
        results = ManualSearchResults(mode: query.mode)
        showUnlikelyResults = false
        fieldsChangedSinceSearch = false
        searchedTitle = trimmedFieldValue(title)
        searchedArtist = trimmedFieldValue(artist)
        lastCandidateFlushUptime = currentUptimeNanoseconds()
        searchStatus = .searching(summary: "Searching…")

        let generation = searchGeneration

        searchTask = Task { @MainActor in
            await runSearch(query, generation: generation)
        }
    }

    func cancelSearch() {
        guard isSearching else { return }
        searchGeneration &+= 1
        flushPendingCandidates(force: true)
        searchTask?.cancel()
        searchTask = nil
        searchStatus = .cancelled
    }

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

    func apply() {
        guard canApply,
              let id = selectionID,
              let result = visibleRows.first(where: { $0.id == id })
        else { return }
        let supporting = results?.supportingLyrics(excluding: result.lyrics) ?? []
        session.select(result.lyrics, writeToiTunesIfAuto: true, supporting: supporting)
        loadedLyrics = result.lyrics
        rebuildVisibleRows()
    }

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

    private func runSearch(_ query: LyricsSearchQuery, generation: Int) async {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                await self.consumeEventStream(query, generation: generation)
                return true
            }

            group.addTask { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                } catch {
                    return false
                }
                guard self.searchGeneration == generation, self.isSearching else {
                    return false
                }
                self.flushPendingCandidates(force: true)
                self.searchStatus = .timedOut
                return false
            }

            _ = await group.next()
            group.cancelAll()
        }
    }

    private func consumeEventStream(_ query: LyricsSearchQuery, generation: Int) async {
        let stream = pipeline.events(for: query)

        var failureMessages: [String] = []
        var completedNormally = false

        for await event in stream {
            guard searchGeneration == generation, isSearching else { break }

            switch event {
            case .providerStarted(let source):
                flushPendingCandidates(force: true)
                updateSearchingSummary(for: source)

            case .candidate(let candidate):
                pendingCandidates.append(candidate)
                flushPendingCandidatesIfNeeded()

            case .providerFinished(let source, _):
                flushPendingCandidates(force: true)
                updateSearchingSummary(afterFinished: source)

            case .providerFailed(let source, let message, _):
                flushPendingCandidates(force: true)
                failureMessages.append("\(source): \(message)")
                updateSearchingSummary(afterFailed: source)

            case .completed:
                flushPendingCandidates(force: true)
                completedNormally = true
            }
        }

        guard searchGeneration == generation, isSearching else { return }

        if completedNormally {
            searchStatus = failureMessages.isEmpty ? .finished : .failed(message: failureMessages.joined(separator: " · "))
        } else if isSearching {
            searchStatus = .cancelled
        }
    }

    private func flushPendingCandidatesIfNeeded() {
        flushPendingCandidates(force: false)
    }

    private func flushPendingCandidates(force: Bool) {
        guard !pendingCandidates.isEmpty else { return }

        let now = currentUptimeNanoseconds()
        let elapsed = now &- lastCandidateFlushUptime
        let shouldFlush = force
            || pendingCandidates.count >= candidateFlushBatchSize
            || elapsed >= candidateFlushIntervalNanoseconds
        guard shouldFlush else { return }

        results?.append(pendingCandidates)
        pendingCandidates.removeAll(keepingCapacity: true)
        lastCandidateFlushUptime = now
        rebuildVisibleRows()
        updateSearchingResultSummary()
    }

    private func rebuildVisibleRows() {
        let rows = (results?.offered(includeUnlikely: showUnlikelyResults, configuration: searchSettings.rankingConfiguration) ?? [])
            .map { LyricsResult(candidate: $0, isLoaded: isLoadedCandidate($0)) }
        let unlikely = results?.unlikelyCount ?? 0
        if unlikelyCount != unlikely {
            unlikelyCount = unlikely
        }
        if visibleRows != rows {
            visibleRows = rows
        }
        invalidateSelectionIfHidden()
    }

    /// Whether `candidate` is the lyrics already loaded for the current track.
    private func isLoadedCandidate(_ candidate: EvaluatedLyricsCandidate) -> Bool {
        guard let loaded = loadedLyrics else { return false }
        return candidate.lyrics.isSameResult(as: loaded)
    }

    private func updateSearchingSummary(for source: String) {
        searchStatus = .searching(summary: "Searching \(source)…")
    }

    private func updateSearchingSummary(afterFinished source: String) {
        let summary = visibleRows.isEmpty
            ? "Searching…"
            : SearchStatus.matchSummary(likely: likelyCount, hiddenUnlikely: hiddenUnlikelyCount)
        searchStatus = .searching(summary: summary)
    }

    private func updateSearchingSummary(afterFailed source: String) {
        let summary = visibleRows.isEmpty
            ? "\(source) failed…"
            : "\(source) failed · \(SearchStatus.partialMatches(visibleRows.count))"
        searchStatus = .searching(summary: summary)
    }

    private func updateSearchingResultSummary() {
        guard case .searching = searchStatus, !visibleRows.isEmpty || unlikelyCount > 0 else { return }
        searchStatus = .searching(summary: SearchStatus.matchSummary(likely: likelyCount, hiddenUnlikely: hiddenUnlikelyCount))
    }

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

    private func resetResults() {
        pendingCandidates.removeAll(keepingCapacity: true)
        visibleRows = []
        unlikelyCount = 0
        clearSelectionPreview()
    }

    private func loadArtwork(for lyrics: Lyrics) {
        let albumKey = albumIdentityKey(for: lyrics)

        // Another likely match from the same album already loaded its cover —
        // reuse it as-is, even when this result points at a different source URL.
        if let albumKey, let cached = albumArtworkCache.object(forKey: albumKey) {
            artwork = cached
            return
        }

        guard let url = lyrics.metadata.artworkURL else {
            artwork = nil
            return
        }
        if let cached = imageCache.object(forKey: url as NSURL) {
            artwork = cached
            if let albumKey { albumArtworkCache.setObject(cached, forKey: albumKey) }
            return
        }
        artwork = nil
        fetchArtwork(url: url) { [weak self] image in
            guard let self, let image else { return }
            self.imageCache.setObject(image, forKey: url as NSURL)
            if let albumKey { self.albumArtworkCache.setObject(image, forKey: albumKey) }
            guard let id = self.selectionID,
                  let selected = self.visibleRows.first(where: { $0.id == id })
            else { return }
            let matchesURL = selected.lyrics.metadata.artworkURL == url
            let matchesAlbum = albumKey != nil && self.albumIdentityKey(for: selected.lyrics) == albumKey
            if matchesURL || matchesAlbum {
                self.artwork = image
            }
        }
    }

    /// A normalized `artist␟album` key shared by every result for the same album.
    /// Returns nil when either tag is missing so callers fall back to per-URL
    /// fetching rather than grouping unrelated results under an empty key.
    private func albumIdentityKey(for lyrics: Lyrics) -> NSString? {
        let album = (lyrics.idTags[.album] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let artist = (lyrics.idTags[.artist] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !album.isEmpty, !artist.isEmpty else { return nil }
        return "\(artist)\u{1f}\(album)" as NSString
    }
}

// MARK: - LyricsResult

struct LyricsResult: Identifiable, Hashable {
    let lyrics: Lyrics
    let evaluation: LyricsCandidateEvaluation
    let isUnlikely: Bool
    /// True when this result is the lyrics already loaded for the current track.
    let isLoaded: Bool

    var id: ObjectIdentifier { ObjectIdentifier(lyrics) }

    var title: String { lyrics.idTags[.title] ?? "[lacking]" }
    var artist: String { lyrics.idTags[.artist] ?? "[lacking]" }
    var source: String { lyrics.metadata.service ?? "[lacking]" }
    var syncIconName: String { evaluation.syncKind == .karaoke ? "music.mic" : "" }

    init(candidate: EvaluatedLyricsCandidate, isLoaded: Bool) {
        self.lyrics = candidate.lyrics
        self.evaluation = candidate.evaluation
        self.isUnlikely = candidate.evaluation.visibility == .unlikely
        self.isLoaded = isLoaded
    }

    // `isLoaded` participates in equality so the Table's `visibleRows != rows`
    // diff still fires when only the loaded indicator moves (e.g. after Apply).
    static func == (lhs: LyricsResult, rhs: LyricsResult) -> Bool {
        lhs.id == rhs.id && lhs.isLoaded == rhs.isLoaded
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isLoaded)
    }
}
