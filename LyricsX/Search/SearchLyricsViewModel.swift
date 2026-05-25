import AppKit
import Combine
@preconcurrency import LyricsKit
import LyricsXFoundation
import MusicPlayer

// MARK: - SearchStatus

enum SearchStatus: Equatable {
    case idle
    case searching(summary: String)
    case foundVisible(count: Int, hiddenUnlikely: Int, rejected: Int)
    case noMatches(hiddenUnlikely: Int, rejected: Int)
    case failed(message: String, visibleCount: Int, hiddenUnlikely: Int, rejected: Int)
    case timedOut(visibleCount: Int, hiddenUnlikely: Int, rejected: Int)
    case cancelled(visibleCount: Int, hiddenUnlikely: Int, rejected: Int)
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
    @Published private(set) var rejectedCount: Int = 0

    var canSearch: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            || !artist.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var hasTrack: Bool { player.currentTrack != nil }

    var canApply: Bool {
        guard hasTrack, let id = selectionID else { return false }
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
    private let ranker = LyricsCandidateRanker()

    private var allCandidates: [EvaluatedLyricsCandidate] = []
    private var pendingCandidates: [EvaluatedLyricsCandidate] = []
    private var likelyRows: [LyricsResult] = []
    private var unlikelyRows: [LyricsResult] = []
    private var currentSearchMode: LyricsSearchMode?
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

    func reloadFromCurrentTrack() {
        guard let track = player.currentTrack else {
            searchGeneration &+= 1
            searchTask?.cancel()
            searchTask = nil
            resetResults()
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

    func search() {
        guard canSearch else { return }

        searchTask?.cancel()

        let trimmedTitle = trimmedFieldValue(title)
        let trimmedArtist = trimmedFieldValue(artist)

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

        let trackDuration = player.currentTrack?.duration
        let requestDuration: TimeInterval = trackDuration ?? 0
        let request = LyricsSearchRequest(
            searchTerm: searchTerm,
            duration: requestDuration,
            limit: 8
        )

        currentSearchMode = mode
        searchGeneration &+= 1
        resetResults()
        showUnlikelyResults = false
        fieldsChangedSinceSearch = false
        searchedTitle = trimmedTitle
        searchedArtist = trimmedArtist
        lastCandidateFlushUptime = currentUptimeNanoseconds()
        searchStatus = .searching(summary: "Searching…")

        let requestedDuration: TimeInterval? = trackDuration
        let requestedAlbum: String? = nil
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

    func cancelSearch() {
        guard isSearching else { return }
        searchGeneration &+= 1
        flushPendingCandidates(force: true)
        searchTask?.cancel()
        searchTask = nil
        searchStatus = .cancelled(
            visibleCount: visibleRows.count,
            hiddenUnlikely: unlikelyCount,
            rejected: rejectedCount
        )
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

    private func runSearch(
        request: LyricsSearchRequest,
        mode: LyricsSearchMode,
        requestedDuration: TimeInterval?,
        requestedAlbum: String?,
        generation: Int
    ) async {
        await withTaskGroup(of: Bool.self) { group in
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
                self.searchStatus = .timedOut(
                    visibleCount: self.visibleRows.count,
                    hiddenUnlikely: self.unlikelyCount,
                    rejected: self.rejectedCount
                )
                return false
            }

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
            if !failureMessages.isEmpty {
                searchStatus = .failed(
                    message: failureMessages.joined(separator: " · "),
                    visibleCount: visibleRows.count,
                    hiddenUnlikely: unlikelyCount,
                    rejected: rejectedCount
                )
            } else if !visibleRows.isEmpty {
                searchStatus = .foundVisible(
                    count: visibleRows.count,
                    hiddenUnlikely: unlikelyCount,
                    rejected: rejectedCount
                )
            } else {
                searchStatus = .noMatches(hiddenUnlikely: unlikelyCount, rejected: rejectedCount)
            }
        } else if isSearching {
            searchStatus = .cancelled(
                visibleCount: visibleRows.count,
                hiddenUnlikely: unlikelyCount,
                rejected: rejectedCount
            )
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

        allCandidates.append(contentsOf: pendingCandidates)
        pendingCandidates.removeAll(keepingCapacity: true)
        lastCandidateFlushUptime = now
        rebuildVisibleRows()
        updateSearchingResultSummary()
    }

    private func rebuildVisibleRows() {
        let ranked = ranker.rankedCandidates(
            allCandidates,
            mode: currentSearchMode ?? .titleOnly(title: ""),
            configuration: searchSettings.rankingConfiguration
        )

        likelyRows = ranked
            .filter { $0.evaluation.visibility != .unlikely }
            .map { LyricsResult(candidate: $0, isUnlikely: false) }
        unlikelyRows = ranked
            .filter { $0.evaluation.visibility == .unlikely }
            .map { LyricsResult(candidate: $0, isUnlikely: true) }
        unlikelyCount = allCandidates.filter { $0.evaluation.visibility == .unlikely }.count
        rejectedCount = allCandidates.filter { $0.evaluation.visibility == .rejected }.count

        let rows = showUnlikelyResults ? likelyRows + unlikelyRows : likelyRows
        if visibleRows != rows {
            visibleRows = rows
        }
        invalidateSelectionIfHidden()
    }

    private func updateSearchingSummary(for source: String) {
        searchStatus = .searching(summary: "Searching \(source)…")
    }

    private func updateSearchingSummary(afterFinished source: String) {
        if !visibleRows.isEmpty {
            let matchLabel = visibleRows.count == 1 ? "match" : "matches"
            let copy = unlikelyCount > 0
                ? "\(visibleRows.count) likely \(matchLabel) · \(unlikelyCount) unlikely hidden"
                : "Found \(visibleRows.count) likely \(matchLabel)"
            searchStatus = .searching(summary: copy)
        } else {
            searchStatus = .searching(summary: "Searching…")
        }
    }

    private func updateSearchingSummary(afterFailed source: String) {
        if !visibleRows.isEmpty {
            let matchLabel = visibleRows.count == 1 ? "match" : "matches"
            searchStatus = .searching(summary: "\(source) failed · showing \(visibleRows.count) partial \(matchLabel)")
        } else {
            searchStatus = .searching(summary: "\(source) failed…")
        }
    }

    private func updateSearchingResultSummary() {
        guard case .searching = searchStatus else { return }
        if !visibleRows.isEmpty {
            let matchLabel = visibleRows.count == 1 ? "match" : "matches"
            let copy = unlikelyCount > 0
                ? "\(visibleRows.count) likely \(matchLabel) · \(unlikelyCount) unlikely hidden"
                : "Found \(visibleRows.count) likely \(matchLabel)"
            searchStatus = .searching(summary: copy)
        } else if unlikelyCount > 0 {
            searchStatus = .searching(summary: "No likely matches · \(unlikelyCount) unlikely hidden")
        }
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
        allCandidates = []
        pendingCandidates.removeAll(keepingCapacity: true)
        likelyRows = []
        unlikelyRows = []
        visibleRows = []
        unlikelyCount = 0
        rejectedCount = 0
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

    var id: ObjectIdentifier { ObjectIdentifier(lyrics) }

    var title: String { lyrics.idTags[.title] ?? "[lacking]" }
    var artist: String { lyrics.idTags[.artist] ?? "[lacking]" }
    var source: String { lyrics.metadata.service ?? "[lacking]" }
    var syncIconName: String { evaluation.syncKind == .karaoke ? "music.mic" : "" }

    init(candidate: EvaluatedLyricsCandidate, isUnlikely: Bool) {
        self.lyrics = candidate.lyrics
        self.evaluation = candidate.evaluation
        self.isUnlikely = isUnlikely
    }

    static func == (lhs: LyricsResult, rhs: LyricsResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
