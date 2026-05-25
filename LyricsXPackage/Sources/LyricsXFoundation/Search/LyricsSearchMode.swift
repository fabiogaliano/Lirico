/// The search intent derived from user-supplied fields.
///
/// Drives evaluator correctness rules and ranker ordering.
/// Title+artist enforces song-level correctness; title-only allows artist
/// mismatch; artist-only is a catalog-browse mode where every song by the
/// artist may be valid.
public enum LyricsSearchMode: Equatable, Sendable {
    case titleAndArtist(title: String, artist: String)
    case titleOnly(title: String)
    case artistOnly(artist: String)
}
