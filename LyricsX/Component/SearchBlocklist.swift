import Foundation
import MusicPlayer

/// Per-track and per-album "do not search lyrics for this" list, with undoable membership.
///
/// Backed by `defaults[.noSearchingTrackIds]` and `defaults[.noSearchingAlbumNames]`. Centralising
/// the mutation surface keeps the four un-block sites from having to copy the same find-and-remove
/// dance, and gives the blocklist concept a real noun in the codebase instead of leaving it as a
/// UserDefaults key pattern strewn across LyricsSession, AppDelegate, and SearchLyricsViewController.
enum SearchBlocklist {

    // MARK: - Query

    static func isBlocked(track: MusicTrack) -> Bool {
        defaults[.noSearchingTrackIds].contains(track.id)
    }

    static func isBlocked(album: String) -> Bool {
        defaults[.noSearchingAlbumNames].contains(album)
    }

    // MARK: - Block

    static func block(track: MusicTrack) {
        defaults[.noSearchingTrackIds].append(track.id)
    }

    static func block(album: String) {
        defaults[.noSearchingAlbumNames].append(album)
    }

    // MARK: - Unblock

    static func unblock(track: MusicTrack) {
        if let index = defaults[.noSearchingTrackIds].firstIndex(of: track.id) {
            defaults[.noSearchingTrackIds].remove(at: index)
        }
    }

    static func unblock(album: String) {
        if let index = defaults[.noSearchingAlbumNames].firstIndex(of: album) {
            defaults[.noSearchingAlbumNames].remove(at: index)
        }
    }
}
