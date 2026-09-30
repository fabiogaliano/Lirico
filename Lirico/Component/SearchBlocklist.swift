import Foundation
import MusicPlayer

/// Per-track and per-album "do not search lyrics for this" list.
///
/// Backed by `.noSearchingTrackIds` and `.noSearchingAlbumNames` in the injected defaults.
struct SearchBlocklist {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isBlocked(track: MusicTrack) -> Bool {
        defaults[.noSearchingTrackIds].contains(track.id)
    }

    func isBlocked(album: String) -> Bool {
        defaults[.noSearchingAlbumNames].contains(album)
    }

    func block(track: MusicTrack) {
        defaults[.noSearchingTrackIds].append(track.id)
    }

    func block(album: String) {
        defaults[.noSearchingAlbumNames].append(album)
    }

    /// Lifts every block that stops `track` from being searched: its own and its album's.
    func unblock(_ track: MusicTrack) {
        defaults[.noSearchingTrackIds].removeAll { $0 == track.id }
        if let album = track.album {
            defaults[.noSearchingAlbumNames].removeAll { $0 == album }
        }
    }
}
