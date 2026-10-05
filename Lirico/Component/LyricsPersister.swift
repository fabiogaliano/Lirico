import Foundation
import LiricoFoundation
import MusicPlayer
import OpenCC

/// Writes lyrics to the user's local disk (saving-path directory) and to the
/// currently playing Apple Music track via its scripting bridge.
///
/// Pulled out of the lyrics-management hub so that the session type owns
/// state, not Apple-Music-specific formatting + scripting glue.
enum LyricsPersister {
    /// Shared base name `"Title - Artist"` used by both the saving-path loader and the writer.
    /// Slashes are replaced with colons so the composed name can't escape into a subdirectory.
    static func baseName(title: String, artist: String) -> String {
        let safeTitle = title.replacingOccurrences(of: "/", with: ":")
        let safeArtist = artist.replacingOccurrences(of: "/", with: ":")
        return "\(safeTitle) - \(safeArtist)"
    }

    /// Filename `Title - Artist.lrcx` used by both the saving-path loader and the writer.
    /// Returns nil when title or artist is missing — the caller treats this as "skip persist".
    static func fileName(for lyrics: Lyrics) -> String? {
        guard let title = lyrics.metadata.title,
              let artist = lyrics.metadata.artist else {
            return nil
        }
        return baseName(title: title, artist: artist) + ".lrcx"
    }

    /// Disk writes run here in order, so a later save of the same lyrics always lands last.
    private static let diskQueue = DispatchQueue(label: "Lirico.LyricsPersister.disk", qos: .utility)
    /// An Apple Event blocks until Music answers, which takes seconds when it's busy; on main,
    /// the whole UI would freeze with it. Serial, so a clear can't overtake an earlier export.
    private static let appleMusicQueue = DispatchQueue(label: "Lirico.LyricsPersister.appleMusic", qos: .utility)

    /// Save `lyrics` to `directory` without blocking the main thread. `needsPersist` is cleared
    /// right away so a second call doesn't queue a duplicate; once written, `localURL` points at
    /// the file, and a failed write sets `needsPersist` again so a later save retries.
    /// Returns nil when there's nothing to write (no title or artist to name the file).
    ///
    /// The directory is resolved by `PersistenceSettings`. Passing it in
    /// rather than reading defaults here keeps this namespace defaults-free.
    @MainActor
    @discardableResult
    static func saveToDisk(_ lyrics: Lyrics, to directory: LyricsStorageDirectory) -> Task<Void, Never>? {
        guard let file = LyricsFile(lyrics, in: directory) else { return nil }
        lyrics.metadata.needsPersist = false
        return Task { @MainActor in
            let written = await withCheckedContinuation { continuation in
                diskQueue.async { continuation.resume(returning: file.write()) }
            }
            if written {
                lyrics.metadata.localURL = file.url
            } else {
                lyrics.metadata.needsPersist = true
            }
        }
    }

    /// Where `saveToDisk` puts `lyrics`, whether or not that save has happened yet.
    @MainActor
    static func fileURL(for lyrics: Lyrics, in directory: LyricsStorageDirectory) -> URL? {
        fileName(for: lyrics).map(directory.url.appendingPathComponent)
    }

    /// Runs after any save still queued, so a save in flight can't recreate the file.
    static func deleteFromDisk(_ url: URL) {
        diskQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// For termination: waits for queued saves, then writes `lyrics` before returning.
    @MainActor
    static func saveToDiskNow(_ lyrics: Lyrics?, to directory: LyricsStorageDirectory) {
        let file = lyrics.flatMap { LyricsFile($0, in: directory) }
        diskQueue.sync { _ = file?.write() }
    }

    /// Write `lyrics` to `track` in Apple Music.
    /// No-op unless `track` came from Apple Music. The caller must check Apple Music is
    /// still playing it (`LyricsSession.canWriteToAppleMusic`): `originalTrack` is only
    /// this track's Apple Music object while Apple Music is playing it.
    ///
    /// The `settings` parameter carries the formatting policy (plain-LRC export
    /// vs. enhanced; include translation or not). Passing it in keeps this
    /// namespace defaults-free in the same shape as `saveToDisk(_:to:)`.
    @MainActor
    static func writeToiTunes(
        _ lyrics: Lyrics,
        to track: MusicTrack,
        settings: ExportSettings,
        converter: ChineseConverter?
    ) {
        let text = AppleMusicExport.text(
            for: lyrics,
            plainLRC: settings.convertToPlainLRC,
            includeTranslation: settings.writeWithTranslation,
            converter: converter?.convert
        )
        setAppleMusicLyrics(text, of: track)
    }

    /// Empty `track`'s lyrics field in Apple Music. Same caller contract as `writeToiTunes`.
    static func clearAppleMusicLyrics(of track: MusicTrack) {
        setAppleMusicLyrics("", of: track)
    }

    private static func setAppleMusicLyrics(_ text: String, of track: MusicTrack) {
        guard let scriptingTrack = track.originalTrack,
              scriptingTrack.responds(to: Selector(("setLyrics:"))) else { return }
        // Only this serial queue sends to it from here on; the embedded-lyrics read at track
        // change happens before any export of that track can be queued.
        nonisolated(unsafe) let target = scriptingTrack
        appleMusicQueue.async {
            target.setValue(text, forKey: "lyrics")
        }
    }
}

/// A save, captured on the main actor (where `Lyrics` lives) so the write can run elsewhere.
private struct LyricsFile: Sendable {
    let directory: URL
    let url: URL
    let requiresSecurityScope: Bool
    let text: String

    @MainActor
    init?(_ lyrics: Lyrics, in directory: LyricsStorageDirectory) {
        guard let name = LyricsPersister.fileName(for: lyrics) else { return nil }
        self.directory = directory.url
        url = directory.url.appendingPathComponent(name)
        requiresSecurityScope = directory.requiresSecurityScope
        text = lyrics.description
    }

    /// Failures (unwritable directory, a file where the directory should be, …) are logged.
    func write() -> Bool {
        if requiresSecurityScope {
            guard directory.startAccessingSecurityScopedResource() else { return false }
        }
        defer {
            if requiresSecurityScope {
                directory.stopAccessingSecurityScopedResource()
            }
        }
        let fileManager = FileManager.default
        do {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: directory.path, isDirectory: &isDir) {
                guard isDir.boolValue else { return false }
            } else {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            }
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            log(error.localizedDescription)
            return false
        }
    }
}
