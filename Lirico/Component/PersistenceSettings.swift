import Foundation

/// A resolved on-disk directory where lyrics should be read from or written to.
///
/// `requiresSecurityScope` is true when the directory comes from the user's
/// custom selection (a folder picked via `NSOpenPanel`, outside the sandbox
/// container). Callers must wrap their file I/O in
/// `start/stopAccessingSecurityScopedResource()` when this flag is set.
struct LyricsStorageDirectory {
    let url: URL
    let requiresSecurityScope: Bool
}

/// Typed view of the local-lyrics storage/loading slice of `UserDefaults`.
///
/// Owns concerns that used to live as ad-hoc `UserDefaults` reads:
///   - default-vs-custom-path selection (gated on `lyricsSavingPathPopUpIndex`)
///   - security-scoped bookmark encode/decode for the user-chosen folder
///   - the fallback to `~/Music/Lirico` when no custom folder is set
///   - whether embedded / beside-track lyrics should be considered
///
/// Persistence (`LyricsPersister`) and loading (`LocalLyricsLoader`) read these
/// through this struct; the preferences UI also binds the plain keys with `@AppStorage`.
/// Unchecked because `UserDefaults` is documented as thread-safe but not marked Sendable.
struct PersistenceSettings: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True when local lyrics embedded in or stored beside the track file
    /// should be considered before the shared saving path.
    var shouldLoadLyricsBesideTrack: Bool {
        get {
            defaults[.loadLyricsBesideTrack]
        }
        nonmutating set {
            defaults[.loadLyricsBesideTrack] = newValue
        }
    }

    /// Resolve the directory where the next `.lrcx` should be written or
    /// where saved-path loading should look. Returns the default
    /// `~/Music/Lirico` when the popup is on index 0 or when the custom
    /// bookmark is absent/stale; otherwise the user-selected directory.
    func storageDirectory() -> LyricsStorageDirectory {
        if defaults[.lyricsSavingPathPopUpIndex] != 0, let url = customSavingDirectory {
            return LyricsStorageDirectory(url: url, requiresSecurityScope: true)
        }
        let userPath = String(cString: getpwuid(getuid()).pointee.pw_dir)
        let defaultURL = URL(fileURLWithPath: userPath).appendingPathComponent("Music/Lirico")
        return LyricsStorageDirectory(url: defaultURL, requiresSecurityScope: false)
    }

    /// Whether `url` lives inside the current storage directory, i.e. Lirico wrote it
    /// rather than the user placing it beside their audio. Compares path components so
    /// `~/Music/Lirico2` doesn't count as inside `~/Music/Lirico`.
    func storageDirectoryContains(_ url: URL) -> Bool {
        let storage = storageDirectory().url.standardizedFileURL.pathComponents
        let path = url.standardizedFileURL.pathComponents
        return path.count > storage.count && Array(path.prefix(storage.count)) == storage
    }

    /// User-selected custom directory, resolved from the security-scoped
    /// bookmark stored in `lyricsCustomSavingPathBookmark`. Returns nil when
    /// the bookmark is absent, stale, or unreadable.
    ///
    /// Exposed for the preferences UI to display the chosen folder's name and
    /// to write a new selection back. Persistence and loading code should call
    /// `storageDirectory()` instead.
    ///
    /// The setter is `nonmutating` because it writes through to `UserDefaults`
    /// rather than mutating the struct's own storage — callers can hold the
    /// settings in a `let` and still update the bookmark.
    var customSavingDirectory: URL? {
        get {
            guard let data = defaults[.lyricsCustomSavingPathBookmark] else {
                return nil
            }
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope],
                    bookmarkDataIsStale: &isStale
                )
                guard !isStale else { return nil }
                return url
            } catch {
                log(error.localizedDescription)
                return nil
            }
        }
        nonmutating set {
            defaults[.lyricsCustomSavingPathBookmark] = try? newValue?.bookmarkData(options: [.withSecurityScope])
        }
    }
}
