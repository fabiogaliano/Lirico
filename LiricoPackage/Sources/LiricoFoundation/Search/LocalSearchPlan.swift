import Foundation

/// Lyrics found in the track's tags or on disk before any remote search runs.
public enum LocalLyricsFind {
    /// Embedded lyrics, a file beside the track, or a saved `.lrcx`.
    case complete(Lyrics)
    /// A saved `.lrc`. The plain format may have lost timing a remote result still has.
    case savedLRC(Lyrics)

    public var lyrics: Lyrics {
        switch self {
        case .complete(let lyrics), .savedLRC(let lyrics): lyrics
        }
    }
}

/// What the local find means for the automatic search that follows it.
public struct LocalSearchPlan {
    public let policy: AutomaticAcceptancePolicy
    /// False for local karaoke: word timing is the best any source offers.
    public let needsRemoteSearch: Bool

    public init(after find: LocalLyricsFind?, title: String, artist: String, duration: TimeInterval?, album: String?) {
        switch find {
        case .complete(let lyrics) where lyrics.isKaraokeTimed:
            policy = .normal
            needsRemoteSearch = false
        case .complete(let lyrics):
            // Line-synced lyrics the user already has only give way to a clearly better match.
            let local = LyricsCandidateEvaluator().evaluate(
                lyrics: lyrics,
                mode: .titleAndArtist(title: title, artist: artist),
                requestedDuration: duration,
                requestedAlbum: album
            )
            policy = .localUpgradeOnly(local: local)
            needsRemoteSearch = true
        case .savedLRC, nil:
            policy = .normal
            needsRemoteSearch = true
        }
    }
}
