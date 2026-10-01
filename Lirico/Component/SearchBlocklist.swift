import Combine
import Foundation
import LiricoFoundation
import MusicPlayer

/// Per-track and per-album "do not search lyrics for this" list.
///
/// Backed by `.noSearchingTrackIds`, `.noSearchingTrackNames` and `.noSearchingAlbumNames`
/// in the injected defaults.
struct SearchBlocklist {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Emits on whichever thread wrote the change.
    var changes: AnyPublisher<Void, Never> {
        defaults.publisher(for: [.noSearchingTrackIds, .noSearchingAlbumNames]).eraseToAnyPublisher()
    }

    var entries: [BlockedEntry] {
        contents.entries
    }

    func isBlocked(track: MusicTrack) -> Bool {
        contents.isBlocked(trackID: track.id)
    }

    func isBlocked(album: String) -> Bool {
        contents.isBlocked(album: album)
    }

    func block(track: MusicTrack) {
        update { $0.block(trackID: track.id, title: track.title, artist: track.artist) }
    }

    func block(album: String) {
        update { $0.block(album: album) }
    }

    /// Lifts every block that stops `track` from being searched: its own and its album's.
    func unblock(_ track: MusicTrack) {
        update { $0.unblock(trackID: track.id, album: track.album) }
    }

    func remove(_ entry: BlockedEntry) {
        update { $0.remove(entry.kind) }
    }

    private var contents: BlocklistContents {
        BlocklistContents(
            trackIDs: defaults[.noSearchingTrackIds],
            trackNames: defaults[.noSearchingTrackNames],
            albums: defaults[.noSearchingAlbumNames]
        )
    }

    private func update(_ change: (inout BlocklistContents) -> Void) {
        var contents = contents
        change(&contents)
        defaults[.noSearchingTrackIds] = contents.trackIDs
        defaults[.noSearchingTrackNames] = contents.trackNames
        defaults[.noSearchingAlbumNames] = contents.albums
    }
}
