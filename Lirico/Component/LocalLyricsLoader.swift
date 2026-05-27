import Foundation
import LiricoFoundation
import MusicPlayer

/// Attempts to satisfy a lyrics request from local sources before any network search runs.
///
/// Sources are tried in priority order:
///   1. Embedded track lyrics (gated on `loadLyricsBesideTrack`)
///   2. `.lrcx` beside the track file (gated on `loadLyricsBesideTrack`)
///   3. `.lrc` beside the track file (gated on `loadLyricsBesideTrack`)
///   4. `.lrcx` in the saving path (always)
///   5. `.lrc` in the saving path (always) — the only source that returns `.foundPartial`
///
/// The trackId blocklist and the album-name blocklist are the caller's responsibility.
enum LocalLyricsLoader {
    /// The outcome of loading from local sources.
    enum Result {
        /// A complete local match — display this and skip network search.
        case found(Lyrics)
        /// Saved-path `.lrc` matched — display this but still run the network search,
        /// since `.lrc` files lack timing precision and a better match may arrive.
        case foundPartial(Lyrics)
        /// No local match — proceed to network search.
        case none
    }

    static func load(
        track: MusicTrack,
        title: String,
        artist: String,
        preparation: LyricsPreparation,
        settings: PersistenceSettings = PersistenceSettings()
    ) -> Result {
        if settings.shouldLoadLyricsBesideTrack {
            if let result = loadEmbedded(track: track, title: title, artist: artist, preparation: preparation) {
                return result
            }
            if let result = loadBesideTrack(track: track, title: title, artist: artist, preparation: preparation) {
                return result
            }
        }
        return loadFromSavingPath(
            title: title,
            artist: artist,
            directory: settings.storageDirectory(),
            preparation: preparation
        )
    }
}

// MARK: - Private sources

private extension LocalLyricsLoader {
    static func loadEmbedded(track: MusicTrack, title: String, artist: String, preparation: LyricsPreparation) -> Result? {
        guard let embeddedLyrics = track.lyrics,
              !embeddedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let lyrics = Lyrics(embeddedLyrics) else {
            return nil
        }
        // Only fill in missing metadata — embedded tags may already carry correct values.
        if lyrics.metadata.title == nil || lyrics.metadata.title?.isEmpty == true {
            lyrics.metadata.title = title
        }
        if lyrics.metadata.artist == nil || lyrics.metadata.artist?.isEmpty == true {
            lyrics.metadata.artist = artist
        }
        preparation.prepare(lyrics)
        return .found(lyrics)
    }

    static func loadBesideTrack(track: MusicTrack, title: String, artist: String, preparation: LyricsPreparation) -> Result? {
        guard let base = track.localFileURL?.deletingPathExtension() else { return nil }
        for ext in ["lrcx", "lrc"] {
            let url = base.appendingPathExtension(ext)
            if let lyrics = parseLyricsFile(at: url, title: title, artist: artist, preparation: preparation) {
                return .found(lyrics)
            }
        }
        return nil
    }

    static func loadFromSavingPath(title: String, artist: String, directory: LyricsStorageDirectory, preparation: LyricsPreparation) -> Result {
        let savingDir = directory.url
        let didAccessSecurityScopedResource: Bool
        if directory.requiresSecurityScope {
            guard savingDir.startAccessingSecurityScopedResource() else { return .none }
            didAccessSecurityScopedResource = true
        } else {
            didAccessSecurityScopedResource = false
        }
        defer {
            if didAccessSecurityScopedResource {
                savingDir.stopAccessingSecurityScopedResource()
            }
        }

        let base = savingDir.appendingPathComponent(LyricsPersister.baseName(title: title, artist: artist))

        if let lyrics = parseLyricsFile(at: base.appendingPathExtension("lrcx"), title: title, artist: artist, preparation: preparation) {
            return .found(lyrics)
        }
        if let lyrics = parseLyricsFile(at: base.appendingPathExtension("lrc"), title: title, artist: artist, preparation: preparation) {
            return .foundPartial(lyrics)
        }
        return .none
    }

    /// Read, parse, and annotate a lyrics file. Returns `nil` if the file is inaccessible or unparseable.
    static func parseLyricsFile(at url: URL, title: String, artist: String, preparation: LyricsPreparation) -> Lyrics? {
        guard let lrcContents = try? String(contentsOf: url, encoding: .utf8),
              let lyrics = Lyrics(lrcContents) else {
            return nil
        }
        // File-based sources always overwrite title and artist, unlike embedded which preserves
        // existing metadata values. This asymmetry matches the original LyricsSession behaviour.
        lyrics.metadata.localURL = url
        lyrics.metadata.title = title
        lyrics.metadata.artist = artist
        preparation.prepare(lyrics)
        return lyrics
    }
}
