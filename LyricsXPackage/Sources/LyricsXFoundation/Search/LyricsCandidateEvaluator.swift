import LyricsKit
import Foundation

// MARK: - Normalization helpers

/// Returns a lowercased, diacritic-folded, punctuation-collapsed token array.
///
/// This is the shared preprocessing step for both title and artist matching.
/// The goal is practical comparability, not equivalence — "lacy" and
/// "drivers license" must NOT become identical tokens.
func normalizedTokens(_ string: String) -> [String] {
    // Fold diacritics + lowercase via linguistic decomposition
    var s = string
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
        .lowercased()
    // Normalize apostrophes / smart quotes / dashes to ASCII equivalents
    s = s
        .replacingOccurrences(of: "\u{2018}", with: "'")
        .replacingOccurrences(of: "\u{2019}", with: "'")
        .replacingOccurrences(of: "\u{201C}", with: "\"")
        .replacingOccurrences(of: "\u{201D}", with: "\"")
        .replacingOccurrences(of: "\u{2013}", with: "-")
        .replacingOccurrences(of: "\u{2014}", with: "-")
    // Collapse all punctuation/symbols (except alphanumerics and spaces) to spaces
    s = s.unicodeScalars.map { scalar in
        let c = Character(scalar)
        if c.isLetter || c.isNumber { return String(c) }
        return " "
    }.joined()
    // Split on whitespace, discard empties
    return s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
}

/// Rejoins normalized tokens into a single string for whole-string comparison.
func normalizedString(_ string: String) -> String {
    normalizedTokens(string).joined(separator: " ")
}

// MARK: - Version-marker stripping

/// Genuine version/variant markers to strip when computing a "core title" for
/// strong-variant matching.  Stripping is additive — the full normalized title
/// is still checked first for exact matches.
///
/// Only real format/variant descriptors belong here.  Artist collaboration
/// separators (feat./ft./featuring/with/and) are NOT included because they
/// appear in real song titles (e.g. "you and i", "you and me") and would make
/// different songs produce the same core token set, causing false strong matches.
/// Those separators are handled in the artist-relation logic instead.
private let versionMarkers: [String] = [
    "acoustic", "live", "remix", "remaster", "remastered",
    "instrumental", "karaoke", "radio edit", "radio", "edit",
    "extended", "original mix", "original", "version", "ver",
    "bonus", "demo", "reprise", "interlude", "intro", "outro",
    "slowed", "reverb", "sped up", "speed up", "nightcore",
    "stereo", "mono",
]

/// Returns the "core" token set by stripping separator-delimited suffixes that
/// match a known version marker and all tokens following them.
///
/// Example: ["lacy", "acoustic"] → ["lacy"]
func coreTokens(_ tokens: [String]) -> [String] {
    // Version/variant info is normally appended after a separator such as "-",
    // "(", "[".  Since separators are collapsed to spaces by normalisation,
    // look for the *first* token that is a pure version marker and drop it and
    // everything after it.  Short titles (≤1 token) are returned unchanged
    // because there is nothing to strip.
    guard tokens.count > 1 else { return tokens }
    for (idx, token) in tokens.enumerated() where idx > 0 {
        if versionMarkers.contains(token) {
            return Array(tokens[..<idx])
        }
    }
    return tokens
}

// MARK: - Title matching

/// Result of a title comparison.
enum TitleMatchLevel {
    /// Fully identical after normalization.
    case exact
    /// Core tokens are identical (variant suffix stripped).
    case strong
    /// Candidate title contains all query tokens as whole tokens (loose overlap).
    case loose
    /// No meaningful overlap.
    case none
}

/// Computes how well `candidateTitle` matches `queryTitle`.
///
/// Matching rules:
/// 1. Exact: normalized strings are identical.
/// 2. Strong: core token sets are identical (e.g. "lacy" matches "lacy acoustic").
/// 3. Loose: all query tokens appear as whole tokens in the candidate token set.
///    For single-token queries (short one-word titles) the query token must
///    appear verbatim in the candidate token set — no substring/fuzzy matching.
/// 4. None: otherwise.
func titleMatchLevel(query: String, candidate: String) -> TitleMatchLevel {
    let qTokens = normalizedTokens(query)
    let cTokens = normalizedTokens(candidate)

    guard !qTokens.isEmpty, !cTokens.isEmpty else { return .none }

    let qNorm = qTokens.joined(separator: " ")
    let cNorm = cTokens.joined(separator: " ")

    // 1. Exact
    if qNorm == cNorm { return .exact }

    // 2. Strong: core tokens identical
    let qCore = coreTokens(qTokens)
    let cCore = coreTokens(cTokens)
    if !qCore.isEmpty, !cCore.isEmpty, qCore.joined(separator: " ") == cCore.joined(separator: " ") {
        return .strong
    }

    // 3. Loose: all query tokens appear as whole tokens in candidate
    let cSet = Set(cTokens)
    let allQueryTokensPresent = qTokens.allSatisfy { cSet.contains($0) }
    if allQueryTokensPresent { return .loose }

    return .none
}

/// 0–100 score for a title at a given match level, scaled within the tier's
/// score band.  Scores reflect remaining textual closeness so candidates can
/// be ranked within the same tier.
func titleScore(query: String, candidate: String, level: TitleMatchLevel) -> Double {
    let qTokens = normalizedTokens(query)
    let cTokens = normalizedTokens(candidate)

    switch level {
    case .exact:
        // Perfect match — maximum score (will land 95–100 after overallScore composition)
        return 100

    case .strong:
        // Deduct for extra tokens in the candidate beyond the core query
        let qCore = coreTokens(qTokens)
        let extraTokens = cTokens.count - qCore.count
        // Band: 88–99 (keeps strong well below exact's 100)
        let penalty = Double(max(0, extraTokens)) * 3.0
        return max(88, 99 - penalty)

    case .loose:
        // Scale by ratio of matched query tokens to candidate length
        let cSet = Set(cTokens)
        let matched = Double(qTokens.filter { cSet.contains($0) }.count)
        let ratio = matched / Double(max(cTokens.count, qTokens.count))
        // Band: 75–87
        return 75 + ratio * 12

    case .none:
        return 0
    }
}

// MARK: - Artist matching

/// Classification of how a candidate artist relates to the queried artist.
enum ArtistRelation {
    /// Primary artist token exactly matches the queried artist.
    case exactPrimary
    /// A non-primary (featured) artist token exactly matches the queried artist,
    /// or the full normalized string contains the other as a whole phrase.
    case exactNonPrimary
    /// Weak/no meaningful match.
    case weak
}

/// Collaboration separators that make the *first* listed artist primary.
private let symmetricSeparators: Set<String> = [",", "、", "&", "and", "/"]
/// Feature separators — tokens after these are non-primary featured artists.
private let featureSeparators: Set<String> = ["feat", "ft", "featuring", "with", "x"]

/// Splits an artist string into (primaryToken, [allNormalizedTokens]).
///
/// "Primary" is defined as the first normalized token before any separator.
/// Collaboration/feature separators are used to divide multi-artist strings.
func splitArtistTokens(_ artist: String) -> (primary: String, all: [String]) {
    let tokens = normalizedTokens(artist)
    var artistGroups: [[String]] = [[]]

    for token in tokens {
        if symmetricSeparators.contains(token) || featureSeparators.contains(token) {
            artistGroups.append([])
        } else {
            artistGroups[artistGroups.count - 1].append(token)
        }
    }

    let groups = artistGroups.filter { !$0.isEmpty }
    let primary = groups.first?.joined(separator: " ") ?? ""
    let all = groups.map { $0.joined(separator: " ") }.filter { !$0.isEmpty }
    return (primary, all)
}

/// Determines the relation between a searched artist and a candidate artist.
func artistRelation(query: String, candidate: String) -> ArtistRelation {
    let (qPrimary, qAll) = splitArtistTokens(query)
    let (cPrimary, cAll) = splitArtistTokens(candidate)

    guard !qPrimary.isEmpty, !cPrimary.isEmpty else { return .weak }

    // Primary exact match — strongest possible relation
    if qPrimary == cPrimary { return .exactPrimary }
    // Query primary appears anywhere in candidate, or vice versa (whole-phrase)
    if cAll.contains(qPrimary) { return .exactNonPrimary }
    if qAll.contains(cPrimary) { return .exactNonPrimary }

    // Cross-check all tokens (handles "A feat. B" vs query "B")
    for qToken in qAll where !qToken.isEmpty {
        for cToken in cAll where !cToken.isEmpty {
            if qToken == cToken {
                // Both primaries weren't equal (checked above), so this is non-primary
                return .exactNonPrimary
            }
        }
    }

    return .weak
}

/// 0–100 artist score for a given relation, used as a tiebreaker within a tier.
func artistScore(relation: ArtistRelation) -> Double {
    switch relation {
    case .exactPrimary:    return 100
    case .exactNonPrimary: return 85
    case .weak:            return 0
    }
}

// MARK: - Duration tiebreaker

/// 0–100 duration tiebreaker score.  Missing duration on either side → 50 (neutral).
func durationScore(requestedDuration: TimeInterval?, candidateDuration: TimeInterval?) -> Double {
    guard let req = requestedDuration, let cand = candidateDuration else { return 50 }
    let dt = abs(req - cand)
    if dt <= 2 { return 100 }
    if dt <= 10 { return 50 + (10 - dt) / 8 * 50 }
    // Penalise strongly mismatched durations inside the same tier
    return max(0, 50 - (dt - 10) * 2)
}

// MARK: - Album tiebreaker

/// 0–100 album tiebreaker score.  Missing album on either side → 50 (neutral).
func albumScore(requestedAlbum: String?, candidateAlbum: String?) -> Double {
    guard let req = requestedAlbum, let cand = candidateAlbum else { return 50 }
    let rNorm = normalizedString(req)
    let cNorm = normalizedString(cand)
    if rNorm.isEmpty || cNorm.isEmpty { return 50 }
    if rNorm == cNorm { return 100 }
    // Weak negative for a clear mismatch
    return 20
}

// MARK: - LyricsCandidateEvaluator

/// Evaluates a single lyrics candidate in the context of a search request.
///
/// The evaluator is stateless and pure: it depends only on the `Lyrics` object,
/// the search mode, and the requested duration/album.  Source priority and
/// karaoke preference are set-level concerns handled by `LyricsCandidateRanker`.
public struct LyricsCandidateEvaluator: Sendable {
    public init() {}

    public func evaluate(
        lyrics: Lyrics,
        mode: LyricsSearchMode,
        requestedDuration: TimeInterval?,
        requestedAlbum: String?
    ) -> LyricsCandidateEvaluation {
        let candidateTitle = lyrics.idTags[.title] ?? ""
        let candidateArtist = lyrics.idTags[.artist] ?? ""
        let candidateAlbum = lyrics.idTags[.album] ?? ""
        let syncKind = lyrics.syncKind

        // Duration from the LRC [length] tag, used for the duration tiebreaker.
        let durScore = durationScore(
            requestedDuration: requestedDuration,
            candidateDuration: lyrics.length
        )
        let albScore = albumScore(
            requestedAlbum: requestedAlbum,
            candidateAlbum: candidateAlbum.isEmpty ? nil : candidateAlbum
        )

        switch mode {
        case .titleAndArtist(let queryTitle, let queryArtist):
            return evaluateTitleAndArtist(
                queryTitle: queryTitle,
                queryArtist: queryArtist,
                candidateTitle: candidateTitle,
                candidateArtist: candidateArtist,
                syncKind: syncKind,
                titleScore: 0,  // computed inside
                artistScore: 0,
                durationScore: durScore,
                albumScore: albScore,
                mode: mode
            )

        case .titleOnly(let queryTitle):
            return evaluateTitleOnly(
                queryTitle: queryTitle,
                candidateTitle: candidateTitle,
                candidateArtist: candidateArtist,
                syncKind: syncKind,
                durationScore: durScore,
                albumScore: albScore,
                mode: mode
            )

        case .artistOnly(let queryArtist):
            return evaluateArtistOnly(
                queryArtist: queryArtist,
                candidateArtist: candidateArtist,
                candidateTitle: candidateTitle,
                syncKind: syncKind,
                durationScore: durScore,
                albumScore: albScore,
                mode: mode
            )
        }
    }

    // MARK: - titleAndArtist evaluation

    private func evaluateTitleAndArtist(
        queryTitle: String,
        queryArtist: String,
        candidateTitle: String,
        candidateArtist: String,
        syncKind: LyricsSyncKind,
        titleScore tScore: Double,
        artistScore aScore: Double,
        durationScore durScore: Double,
        albumScore albScore: Double,
        mode: LyricsSearchMode
    ) -> LyricsCandidateEvaluation {

        let titleLevel = titleMatchLevel(query: queryTitle, candidate: candidateTitle)
        let tRawScore = titleScore(query: queryTitle, candidate: candidateTitle, level: titleLevel)

        // Artist relation — missing candidate artist is treated as weak but not
        // automatically rejecting; the tier adjustments below handle that case.
        let hasCandidateArtist = !candidateArtist.isEmpty
        let relation: ArtistRelation = hasCandidateArtist
            ? artistRelation(query: queryArtist, candidate: candidateArtist)
            : .weak
        let aRawScore = hasCandidateArtist ? artistScore(relation: relation) : 0

        let strongArtist = relation == .exactPrimary || relation == .exactNonPrimary

        func makeEval(
            visibility: LyricsCandidateVisibility,
            tier: LyricsCandidateMatchTier,
            titleS: Double,
            artistS: Double,
            overall: Double,
            rejection: LyricsCandidateRejectionReason? = nil
        ) -> LyricsCandidateEvaluation {
            LyricsCandidateEvaluation(
                mode: mode,
                visibility: visibility,
                matchTier: tier,
                syncKind: syncKind,
                titleScore: titleS,
                artistScore: artistS,
                durationScore: durScore,
                albumScore: albScore,
                overallScore: overall,
                rejectionReason: rejection
            )
        }

        switch titleLevel {
        case .exact:
            if strongArtist {
                // Best possible result
                let overall = blendScores(
                    title: tRawScore, artist: aRawScore,
                    duration: durScore, album: albScore,
                    titleWeight: 0.55, artistWeight: 0.30
                )
                // Non-overlapping bands guarantee primary always outranks non-primary
                // within the same tier, regardless of duration/album tiebreakers.
                // primary: 96–100, non-primary: 92–95 (ceiling strictly below primary floor).
                let cappedOverall = relation == .exactPrimary
                    ? clamp(overall, in: 96...100)
                    : clamp(overall, in: 92...95)
                return makeEval(
                    visibility: .normal,
                    tier: .exactTitleArtist,
                    titleS: tRawScore, artistS: aRawScore,
                    overall: cappedOverall
                )
            } else if !hasCandidateArtist {
                // Exact title + unknown artist: strong but below confirmed exact
                let overall = blendScores(
                    title: tRawScore, artist: 50,
                    duration: durScore, album: albScore,
                    titleWeight: 0.65, artistWeight: 0.10
                )
                return makeEval(
                    visibility: .normal,
                    tier: .strongTitleArtist,
                    titleS: tRawScore, artistS: 50,
                    overall: clamp(overall, in: 88...92)
                )
            } else {
                // Exact title, but artist clearly doesn't match → unlikely
                return makeEval(
                    visibility: .unlikely,
                    tier: .rejected,
                    titleS: tRawScore, artistS: aRawScore,
                    overall: 0,
                    rejection: .artistMismatch
                )
            }

        case .strong:
            if strongArtist {
                let overall = blendScores(
                    title: tRawScore, artist: aRawScore,
                    duration: durScore, album: albScore,
                    titleWeight: 0.55, artistWeight: 0.30
                )
                return makeEval(
                    visibility: .normal,
                    tier: .strongTitleArtist,
                    titleS: tRawScore, artistS: aRawScore,
                    overall: clamp(overall, in: 88...94)
                )
            } else if !hasCandidateArtist {
                let overall = blendScores(
                    title: tRawScore, artist: 50,
                    duration: durScore, album: albScore,
                    titleWeight: 0.65, artistWeight: 0.10
                )
                return makeEval(
                    visibility: .looseFallback,
                    tier: .looseTitleArtist,
                    titleS: tRawScore, artistS: 50,
                    overall: clamp(overall, in: 75...84)
                )
            } else {
                // Strong title but artist mismatch → unlikely
                return makeEval(
                    visibility: .unlikely,
                    tier: .rejected,
                    titleS: tRawScore, artistS: aRawScore,
                    overall: 0,
                    rejection: .artistMismatch
                )
            }

        case .loose:
            if strongArtist {
                let overall = blendScores(
                    title: tRawScore, artist: aRawScore,
                    duration: durScore, album: albScore,
                    titleWeight: 0.55, artistWeight: 0.30
                )
                return makeEval(
                    visibility: .looseFallback,
                    tier: .looseTitleArtist,
                    titleS: tRawScore, artistS: aRawScore,
                    overall: clamp(overall, in: 75...87)
                )
            } else {
                return makeEval(
                    visibility: .unlikely,
                    tier: .rejected,
                    titleS: tRawScore, artistS: aRawScore,
                    overall: 0,
                    rejection: candidateTitle.isEmpty ? .noMeaningfulContent : .titleMismatch
                )
            }

        case .none:
            // No meaningful title overlap → rejected regardless of artist
            return makeEval(
                visibility: .rejected,
                tier: .rejected,
                titleS: 0, artistS: aRawScore,
                overall: 0,
                rejection: .titleMismatch
            )
        }
    }

    // MARK: - titleOnly evaluation

    private func evaluateTitleOnly(
        queryTitle: String,
        candidateTitle: String,
        candidateArtist: String,
        syncKind: LyricsSyncKind,
        durationScore durScore: Double,
        albumScore albScore: Double,
        mode: LyricsSearchMode
    ) -> LyricsCandidateEvaluation {

        let titleLevel = titleMatchLevel(query: queryTitle, candidate: candidateTitle)
        let tRawScore = titleScore(query: queryTitle, candidate: candidateTitle, level: titleLevel)

        // Artist is a tiebreaker only in titleOnly mode — it cannot reject a
        // candidate whose title matches.
        let aRawScore: Double
        if candidateArtist.isEmpty {
            aRawScore = 50
        } else {
            // Use score as a soft tiebreaker without a query artist to compare against;
            // give a neutral mid score since we have no query to compare against.
            aRawScore = 50
        }

        func makeEval(
            visibility: LyricsCandidateVisibility,
            tier: LyricsCandidateMatchTier,
            overall: Double,
            rejection: LyricsCandidateRejectionReason? = nil
        ) -> LyricsCandidateEvaluation {
            LyricsCandidateEvaluation(
                mode: mode,
                visibility: visibility,
                matchTier: tier,
                syncKind: syncKind,
                titleScore: tRawScore,
                artistScore: aRawScore,
                durationScore: durScore,
                albumScore: albScore,
                overallScore: overall,
                rejectionReason: rejection
            )
        }

        switch titleLevel {
        case .exact:
            let overall = blendScores(
                title: tRawScore, artist: aRawScore,
                duration: durScore, album: albScore,
                titleWeight: 0.70, artistWeight: 0.05
            )
            return makeEval(
                visibility: .normal,
                tier: .titleOnly,
                overall: clamp(overall, in: 95...100)
            )

        case .strong:
            let overall = blendScores(
                title: tRawScore, artist: aRawScore,
                duration: durScore, album: albScore,
                titleWeight: 0.70, artistWeight: 0.05
            )
            return makeEval(
                visibility: .normal,
                tier: .titleOnly,
                overall: clamp(overall, in: 88...94)
            )

        case .loose:
            let overall = blendScores(
                title: tRawScore, artist: aRawScore,
                duration: durScore, album: albScore,
                titleWeight: 0.70, artistWeight: 0.05
            )
            return makeEval(
                visibility: .looseFallback,
                tier: .titleOnly,
                overall: clamp(overall, in: 75...87)
            )

        case .none:
            return makeEval(
                visibility: .rejected,
                tier: .rejected,
                overall: 0,
                rejection: .titleMismatch
            )
        }
    }

    // MARK: - artistOnly evaluation

    private func evaluateArtistOnly(
        queryArtist: String,
        candidateArtist: String,
        candidateTitle: String,
        syncKind: LyricsSyncKind,
        durationScore durScore: Double,
        albumScore albScore: Double,
        mode: LyricsSearchMode
    ) -> LyricsCandidateEvaluation {

        guard !candidateArtist.isEmpty else {
            return LyricsCandidateEvaluation(
                mode: mode,
                visibility: .unlikely,
                matchTier: .rejected,
                syncKind: syncKind,
                titleScore: 0,
                artistScore: 0,
                durationScore: durScore,
                albumScore: albScore,
                overallScore: 0,
                rejectionReason: .artistMismatch
            )
        }

        let relation = artistRelation(query: queryArtist, candidate: candidateArtist)
        let aRawScore = artistScore(relation: relation)

        // Title score is used for A–Z tiebreaking within artist catalog, not for rejection.
        // Give a neutral score since title correctness is irrelevant in artist-only mode.
        let tRawScore: Double = candidateTitle.isEmpty ? 0 : 50

        func makeEval(
            visibility: LyricsCandidateVisibility,
            tier: LyricsCandidateMatchTier,
            overall: Double,
            rejection: LyricsCandidateRejectionReason? = nil
        ) -> LyricsCandidateEvaluation {
            LyricsCandidateEvaluation(
                mode: mode,
                visibility: visibility,
                matchTier: tier,
                syncKind: syncKind,
                titleScore: tRawScore,
                artistScore: aRawScore,
                durationScore: durScore,
                albumScore: albScore,
                overallScore: overall,
                rejectionReason: rejection
            )
        }

        switch relation {
        case .exactPrimary:
            let overall = blendScores(
                title: tRawScore, artist: aRawScore,
                duration: durScore, album: albScore,
                titleWeight: 0.05, artistWeight: 0.75
            )
            return makeEval(
                visibility: .normal,
                tier: .exactArtistCatalog,
                overall: clamp(overall, in: 85...100)
            )

        case .exactNonPrimary:
            let overall = blendScores(
                title: tRawScore, artist: aRawScore,
                duration: durScore, album: albScore,
                titleWeight: 0.05, artistWeight: 0.75
            )
            return makeEval(
                visibility: .normal,
                tier: .looseArtistCatalog,
                overall: clamp(overall, in: 70...84)
            )

        case .weak:
            return makeEval(
                visibility: .unlikely,
                tier: .rejected,
                overall: 0,
                rejection: .artistMismatch
            )
        }
    }
}

// MARK: - Score blending helpers

/// Blends title, artist, duration, and album scores into a single 0–100 value.
/// Duration and album weights are the remaining weight after title+artist.
private func blendScores(
    title: Double,
    artist: Double,
    duration: Double,
    album: Double,
    titleWeight: Double,
    artistWeight: Double
) -> Double {
    let remainder = max(0, 1 - titleWeight - artistWeight)
    let durationWeight = remainder * 0.7
    let albumWeight = remainder * 0.3
    return title * titleWeight
        + artist * artistWeight
        + duration * durationWeight
        + album * albumWeight
}

/// Clamps a value to a closed range.
private func clamp(_ value: Double, in range: ClosedRange<Double>) -> Double {
    min(range.upperBound, max(range.lowerBound, value))
}
