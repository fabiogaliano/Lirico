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
///   - the fallback to `~/Music/LyricsX` when no custom folder is set
///   - whether embedded / beside-track lyrics should be considered
///
/// Persistence (`LyricsPersister`), loading (`LocalLyricsLoader`), and the
/// preferences UI all consume this struct; no other code in the app should
/// reach into `defaults` for local-lyrics storage/loading concerns.
struct PersistenceSettings {
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
    /// `~/Music/LyricsX` when the popup is on index 0 or when the custom
    /// bookmark is absent/stale; otherwise the user-selected directory.
    func storageDirectory() -> LyricsStorageDirectory {
        if defaults[.lyricsSavingPathPopUpIndex] != 0, let url = customSavingDirectory {
            return LyricsStorageDirectory(url: url, requiresSecurityScope: true)
        }
        let userPath = String(cString: getpwuid(getuid()).pointee.pw_dir)
        let defaultURL = URL(fileURLWithPath: userPath).appendingPathComponent("Music/LyricsX")
        return LyricsStorageDirectory(url: defaultURL, requiresSecurityScope: false)
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
