@preconcurrency import LyricsKit

// MARK: - LyricsCandidateVisibility

/// How a candidate is presented in the result set.
///
/// Rejected candidates are never shown; unlikely candidates are hidden behind
/// the "Show unlikely results" toggle; looseFallback candidates are shown only
/// when no normal (exact/strong) candidates exist for the same search.
public enum LyricsCandidateVisibility: Equatable, Sendable {
    case normal
    case looseFallback
    case unlikely
    case rejected
}

// MARK: - LyricsCandidateMatchTier

/// The correctness tier of a candidate relative to the search request.
///
/// `titleBasedPriority` provides an integer ordering for title-based ranking;
/// artist-only ranking uses a separate catalog-tier comparison instead.
public enum LyricsCandidateMatchTier: Equatable, Sendable {
    case exactTitleArtist
    case strongTitleArtist
    case looseTitleArtist
    case titleOnly
    case exactArtistCatalog
    case looseArtistCatalog
    case rejected

    /// Integer sort priority for title-based (titleAndArtist / titleOnly) ranking.
    /// Higher value = ranked first. Artist-only ranking ignores this property.
    public var titleBasedPriority: Int {
        switch self {
        case .exactTitleArtist:   600
        case .strongTitleArtist:  500
        case .titleOnly:          400
        case .looseTitleArtist:   300
        case .exactArtistCatalog: 200
        case .looseArtistCatalog: 100
        case .rejected:             0
        }
    }
}

// MARK: - LyricsCandidateRejectionReason

/// Why a candidate was rejected or downgraded.
public enum LyricsCandidateRejectionReason: Equatable, Sendable {
    case titleMismatch
    case artistMismatch
    case noMeaningfulContent
}

// MARK: - LyricsCandidateEvaluation

/// Per-candidate evaluation result produced by `LyricsCandidateEvaluator`.
///
/// Tier and visibility encode correctness; the numeric scores are used only
/// for ordering within comparable tiers and for the karaoke preference window.
/// Duration and album scores are tiebreakers only — they never promote a
/// wrong-title or wrong-artist candidate.
public struct LyricsCandidateEvaluation: Equatable, Sendable {
    public let mode: LyricsSearchMode
    public let visibility: LyricsCandidateVisibility
    public let matchTier: LyricsCandidateMatchTier
    public let syncKind: LyricsSyncKind
    /// 0–100 title similarity score.
    public let titleScore: Double
    /// 0–100 artist similarity score.
    public let artistScore: Double
    /// Tiebreaker: 0–100 duration proximity score.
    public let durationScore: Double
    /// Tiebreaker: 0–100 album match score.
    public let albumScore: Double
    /// Composite 0–100 score reflecting correctness + tiebreakers.
    public let overallScore: Double
    public let rejectionReason: LyricsCandidateRejectionReason?
}

// MARK: - EvaluatedLyricsCandidate

/// A lyrics candidate paired with its per-request evaluation.
///
/// Identity and equality are by object reference (`ObjectIdentifier`) so that
/// two evaluated wrappers for the same `Lyrics` instance are always the same
/// candidate regardless of evaluation differences.
public struct EvaluatedLyricsCandidate: Identifiable, Hashable {
    public let lyrics: Lyrics
    public let evaluation: LyricsCandidateEvaluation
    /// Zero-based position in the stream; used as the stable final tiebreaker.
    public let arrivalIndex: Int

    public var id: ObjectIdentifier { ObjectIdentifier(lyrics) }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public init(lyrics: Lyrics, evaluation: LyricsCandidateEvaluation, arrivalIndex: Int) {
        self.lyrics = lyrics
        self.evaluation = evaluation
        self.arrivalIndex = arrivalIndex
    }
}
