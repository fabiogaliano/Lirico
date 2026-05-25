import AppKit
import Combine
import LyricsXFoundation
import MusicPlayer

/// View-model for the Search Lyrics window.
///
/// Holds the state of the Search Lyrics window. `Lyrics` is a reference type
/// from `LyricsKit`, so `LyricsResult` wraps it solely to give SwiftUI a
/// stable identity for selection.
@MainActor
final class SearchLyricsViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published private(set) var results: [LyricsResult] = []
    @Published var selectionID: LyricsResult.ID?
    @Published private(set) var preview: String = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isSearching: Bool = false

    var canSearch: Bool { !title.isEmpty }
    var hasTrack: Bool { player.currentTrack != nil }
    var canApply: Bool { hasTrack && selectionID != nil }

    private let player: PlayerHandle
    private let session: LyricsSession
    private let pipeline: LyricsSearchPipeline
    private let searchSettings: SearchSettings

    private var rawResults: [Lyrics] = []
    private var searchTask: Task<Void, Never>?
    private var searchRequest: LyricsSearchRequest?
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
    }

    /// Refresh title/artist from the current track and re-run the search when
    /// they changed. Matches the old `viewWillAppear` / `reloadKeyword` flow:
    /// the window controller calls this on every `showWindow(_:)`.
    func reloadFromCurrentTrack() {
        guard let track = player.currentTrack else {
            searchTask?.cancel()
            rawResults = []
            results = []
            title = ""
            artist = ""
            selectionID = nil
            preview = ""
            artwork = nil
            searchRequest = nil
            isSearching = false
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
        searchTask?.cancel()
        rawResults = []
        results = []
        selectionID = nil
        preview = ""
        artwork = nil

        let track = player.currentTrack
        let duration = track?.duration ?? 0
        let req = LyricsSearchRequest(
            searchTerm: .info(title: title, artist: artist),
            duration: duration,
            limit: 8
        )
        searchRequest = req
        isSearching = true

        searchTask = Task { @MainActor in
            defer {
                if searchRequest == req {
                    isSearching = false
                }
            }
            do {
                for try await lyrics in pipeline.candidates(for: req) {
                    receive(lyrics: lyrics)
                }
            } catch is CancellationError {
                // Search was cancelled by a newer request or by clearing the window.
            } catch {
                log(error.localizedDescription)
            }
        }
    }

    func apply() {
        guard let id = selectionID,
              let result = results.first(where: { $0.id == id }),
              player.currentTrack != nil
        else { return }
        if let track = player.currentTrack {
            SearchBlocklist.unblock(track: track)
            SearchBlocklist.unblock(album: track.album ?? "")
        }
        session.select(result.lyrics, writeToiTunesIfAuto: true)
    }

    /// Recompute preview text and artwork for the current selection. Called by
    /// the view when `selectionID` changes.
    func updatePreview() {
        guard let id = selectionID,
              let result = results.first(where: { $0.id == id })
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

    private func receive(lyrics: Lyrics) {
        guard lyrics.metadata.request == searchRequest else { return }
        LyricsSelector.shared.insert(lyrics, into: &rawResults, settings: searchSettings)
        results = rawResults.map(LyricsResult.init)
    }

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
            // The user may have changed selection while the fetch was in flight;
            // only adopt the result if it still matches.
            if self.selectionID.flatMap({ id in self.results.first(where: { $0.id == id }) })?.lyrics.metadata.artworkURL == url {
                self.artwork = image
            }
        }
    }
}

/// Identifiable wrapper around `Lyrics` for SwiftUI selection. Lyrics is a
/// reference type, so we identify it by its object pointer rather than
/// inventing a parallel UUID.
struct LyricsResult: Identifiable, Hashable {
    let lyrics: Lyrics

    var id: ObjectIdentifier { ObjectIdentifier(lyrics) }
    var title: String { lyrics.idTags[.title] ?? "[lacking]" }
    var artist: String { lyrics.idTags[.artist] ?? "[lacking]" }
    var source: String { lyrics.metadata.service ?? "[lacking]" }

    static func == (lhs: LyricsResult, rhs: LyricsResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
