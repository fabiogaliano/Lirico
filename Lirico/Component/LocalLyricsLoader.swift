import Foundation
import LiricoFoundation
import LyricsCore
import MusicPlayer

/// Attempts to satisfy a lyrics request from local sources before any network search runs.
///
/// Sources are tried in priority order:
///   1. Embedded track lyrics (gated on `loadLyricsBesideTrack`)
///   2. `.lrcx` beside the track file (gated on `loadLyricsBesideTrack`)
///   3. `.lrc` beside the track file (gated on `loadLyricsBesideTrack`)
///   4. `.lrcx` in the saving path (always)
///   5. `.lrc` in the saving path (always) — the only source that returns `.savedLRC`
///
/// The trackId blocklist and the album-name blocklist are the caller's responsibility.
enum LocalLyricsLoader {
    static func load(
        track: MusicTrack,
        title: String,
        artist: String,
        preparation: LyricsPreparation,
        settings: PersistenceSettings
    ) -> LocalLyricsFind? {
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

// MARK: - LocalLyrics

/// Local lyrics for a track, and what they mean for the remote search that may follow.
struct LocalLyrics: Sendable {
    let lyrics: Lyrics?
    let policy: AutomaticAcceptancePolicy
    /// False for local karaoke: word timing is the best any source offers.
    let needsRemoteSearch: Bool

    static func resolve(
        track: MusicTrack,
        title: String,
        artist: String,
        preparation: LyricsPreparation,
        persistenceSettings: PersistenceSettings
    ) -> LocalLyrics {
        let find = LocalLyricsLoader.load(
            track: track,
            title: title,
            artist: artist,
            preparation: preparation,
            settings: persistenceSettings
        )
        // For diagnostics only: not a remote source-priority entry, so it takes no part in ranking.
        find?.lyrics.metadata.service = localSourceName(for: find?.lyrics, persistenceSettings: persistenceSettings)
        let plan = LocalSearchPlan(after: find, title: title, artist: artist, duration: track.duration, album: track.album)
        return LocalLyrics(lyrics: find?.lyrics, policy: plan.policy, needsRemoteSearch: plan.needsRemoteSearch)
    }

    /// "Embedded" when read from the track's own tags, "Local Storage" when saved in
    /// Lirico's directory, otherwise "Beside Track".
    private static func localSourceName(for lyrics: Lyrics?, persistenceSettings: PersistenceSettings) -> String {
        guard let localURL = lyrics?.metadata.localURL else { return "Embedded" }
        return persistenceSettings.storageDirectoryContains(localURL) ? "Local Storage" : "Beside Track"
    }
}

// MARK: - Private sources

private extension LocalLyricsLoader {
    static func loadEmbedded(track: MusicTrack, title: String, artist: String, preparation: LyricsPreparation) -> LocalLyricsFind? {
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
        return .complete(lyrics)
    }

    static func loadBesideTrack(track: MusicTrack, title: String, artist: String, preparation: LyricsPreparation) -> LocalLyricsFind? {
        guard let base = track.localFileURL?.deletingPathExtension() else { return nil }
        for ext in ["lrcx", "lrc"] {
            let url = base.appendingPathExtension(ext)
            if let lyrics = parseLyricsFile(at: url, title: title, artist: artist, preparation: preparation) {
                return .complete(lyrics)
            }
        }
        return nil
    }

    static func loadFromSavingPath(
        title: String,
        artist: String,
        directory: LyricsStorageDirectory,
        preparation: LyricsPreparation
    ) -> LocalLyricsFind? {
        let savingDir = directory.url
        let didAccessSecurityScopedResource: Bool
        if directory.requiresSecurityScope {
            guard savingDir.startAccessingSecurityScopedResource() else { return nil }
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
            return .complete(lyrics)
        }
        if let lyrics = parseLyricsFile(at: base.appendingPathExtension("lrc"), title: title, artist: artist, preparation: preparation) {
            return .savedLRC(lyrics)
        }
        return nil
    }

    /// Read, parse, and annotate a lyrics file. Returns `nil` if the file is inaccessible or unparseable.
    static func parseLyricsFile(at url: URL, title: String, artist: String, preparation: LyricsPreparation) -> Lyrics? {
        guard let lrcContents = try? String(contentsOf: url, encoding: .utf8),
              let lyrics = Lyrics(lrcContents) else {
            return nil
        }
        // Labelled with the playing track, not the file's own tags: saving names the file from
        // these, so an offset tweak re-saves to the name it was found under.
        lyrics.metadata.localURL = url
        lyrics.metadata.title = title
        lyrics.metadata.artist = artist
        preparation.prepare(lyrics)
        return lyrics
    }
}
