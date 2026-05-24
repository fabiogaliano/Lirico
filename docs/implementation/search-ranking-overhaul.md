# Search Ranking Overhaul

## Framing note

This is a future-state implementation plan for fixing LyricsX search correctness, karaoke prioritization, and manual-search feedback. The proposed evaluator/ranker does not exist yet. Current search relies mostly on provider output, `Lyrics.quality`, optional strict filtering, and source priority.

The core product invariant for this work:

> A result for the wrong song must not beat, replace, or visually outrank a result for the requested song.

A secondary invariant:

> When two candidates are similarly correct, prefer karaoke/word-timed lyrics over line-synced lyrics.

## Current repo state

### Search construction

- `LyricsX/Component/AppContainer.swift` creates one shared `LyricsSearchPipeline` and injects it into both `LyricsSession` and `SearchLyricsWindowController`.
- `LyricsX/Component/LyricsSearchPipeline.swift` owns provider setup and streams prepared `Lyrics` candidates.
- `LyricsX/Component/LyricsSelector.swift` owns source-order normalization, priority comparison, and ordered insertion.

### Automatic search

- `LyricsX/Component/LyricsSession.swift` runs automatic search from `currentTrackChanged()`.
- It first tries `LocalLyricsLoader.load(...)`.
- If a complete local result is found, current behavior stops network search.
- If a saved-path `.lrc` partial result is found, current behavior displays it and still runs network search.
- Remote candidates are accepted through `accept(lyrics:request:)`, which uses `LyricsSelector.shared.hasHigherPriority(...)`.
- The chosen candidate becomes `currentLyrics`.

### Manual search

- `LyricsX/Search/SearchLyricsWindowController.swift` calls `viewModel.reloadFromCurrentTrack()` whenever the window is shown.
- `LyricsX/Search/SearchLyricsViewModel.swift` starts a search when title/artist changes on open.
- Manual search currently creates:

```swift
LyricsSearchRequest(
    searchTerm: .info(title: title, artist: artist),
    duration: duration,
    limit: 8
)
```

- Manual search currently calls:

```swift
pipeline.candidates(for: req, strict: false)
```

So manual search deliberately lets unmatched provider results through.

### Current strict matching

- `LyricsSearchPipeline` only filters with `Lyrics.isMatched()` when `strict == true` and `settings.strictSearchEnabled` is enabled.
- Automatic search passes `strict: true`.
- Manual search passes `strict: false`.
- Strict matching comes from LyricsKit and is title/artist similarity based; it is not a full app-level ranking policy.
- This preference is pre-production and should be removed as part of this overhaul; the new evaluator replaces it.

### Floating / desktop lyrics display

- Floating desktop lyrics are not directly bound to the manual search result list.
- They display `LyricsSession.currentLyrics`.
- Manual search affects floating lyrics only after `SearchLyricsViewModel.apply()` calls:

```swift
session.select(result.lyrics, writeToiTunesIfAuto: true)
```

- Automatic search directly updates `currentLyrics`, so wrong automatic matches become visible in the floating desktop lyrics.

### Karaoke support

LyricsX already supports karaoke/word-timed lyrics.

- LyricsKit parses `[tt]` attachments into `LyricsLine.Attachments.InlineTimeTag`.
- `LyricsLine.Attachments.Tag.timetag` is raw tag `"tt"`.
- `LyricsX/Controller/KaraokeLyricsController.swift` checks:

```swift
line.line.attachments.timetag
```

and calls:

```swift
upperTextField.setProgressAnimation(...)
```

- Line-synced lyrics have timestamps per line but no `timetag` attachments.

## Problems to solve

1. Manual search shows unrelated songs, e.g. searching `lacy / Olivia Rodrigo` can show `drivers license` and `drop dead` above exact `lacy` results.
2. Automatic search can select wrong candidates because it shares weak ranking primitives.
3. Source priority can currently beat candidate correctness.
4. `Lyrics.quality` is not a sufficient app-level correctness policy and should not be the main ranking key.
5. Karaoke candidates are not visibly marked in manual search.
6. Karaoke candidates are not intentionally preferred in automatic search.
7. Manual search UI gives unclear feedback:
   - opening the window auto-starts search,
   - button disables during search,
   - failures/timeouts are not visible,
   - partial/provider progress is unclear.
8. Manual search cannot search by artist only because `canSearch` requires a non-empty title.

## Goals

- Build one shared candidate evaluator used by automatic and manual search.
- Filter wrong-song candidates out of normal title-based results.
- Prefer karaoke/word-timed lyrics when match quality is reasonably close.
- Preserve source priority as a near-equal tiebreaker only, never as a correctness override, for both automatic selection and manual result ordering.
- Support title+artist, title-only, and artist-only searches.
- Make manual search progress, cancellation, failures, and filtered results clear.
- Add a mic symbol to karaoke results in manual search.
- Keep implementation incremental and testable.

## Non-goals

- Do not make provider-specific rich-timing work part of this overhaul. LyricsX should detect karaoke/word-timed lyrics generically from parsed inline time tags, regardless of source.
- Do not add Musixmatch richsync work in this plan. Musixmatch remains an ordinary provider; if it returns only line-timed lyrics, the app treats it as line-synced.
- Do not group duplicate results into expandable sections in this pass.
- Do not remove source priority preferences.
- Do not require a perfect global normalization system for every possible provider typo.

## Cross-repo dependency plan

This overhaul spans LyricsX and the local LyricsKit checkout at:

```text
/Users/f/Core/dev/projects/LyricsKit
```

LyricsX currently pins LyricsKit through Xcode SPM resolution, but the local LyricsKit `main` branch is already ahead of the resolved dependency. It has HTTP-client injection, provider tests, concurrent group search, stream cancellation via `onTermination`, request identity/origin, and search plugins.

Required LyricsKit work for this overhaul:

- Add a first-class non-throwing provider event API on `LyricsProviders.Group`, while preserving the existing `lyrics(for:)` API as a candidate-only convenience wrapper.
- Keep individual provider APIs candidate-oriented; do not require every provider to implement an event protocol in this pass.
- Construct `LyricsProviders.Group` from explicit provider descriptors so the group owns source names for event emission.
- Include provider started, candidate yielded, provider finished, provider failed, and completed events.
- Represent provider failures as event values rather than thrown stream errors, so partial results stay available and one failed source does not cancel other sources.
- Include the `LyricsSearchRequest` on provider start/finish/failure events so plugin-derived searches remain traceable.
- Keep cancellation cooperative and covered by tests.
- Add an LRCLIB exact lookup path without removing broad search: for title+artist searches with album and duration available, run `/api/get` alongside the existing `/api/search` path. Exact lookup improves precision, while broad search remains available for safety and alternatives.

Required LyricsX integration work after the local LyricsKit update:

- Update provider construction to the newer LyricsKit service API.
- Pass album metadata through `LyricsSearchRequest.userInfo` when available so LRCLIB exact lookup can use it.
- Map raw LyricsKit provider events into app-level evaluated `LyricsSearchEvent` values.

LyricsKit should define the shared album metadata convention:

```swift
extension LyricsSearchRequest {
    public enum UserInfoKey {
        public static let albumName = "albumName"
    }

    public var albumName: String? {
        userInfo[UserInfoKey.albumName]
    }
}
```

LyricsX should set this key from `MusicTrack.album` only for automatic current-track searches. Manual search requests must leave album unset, including the auto-search that runs when the Search Lyrics window opens.

Album metadata rules:

- Automatic current-track search includes album when available.
- Manual search never includes album in this pass.
- Manual search remains a title/artist lookup surface until the UI explicitly adds an album field in a future pass.

LRCLIB lookup rules:

- Always keep the existing `/api/search` path for title+artist and keyword searches.
- When title, artist, album, and duration are all available, also run `/api/get` for the exact track signature.
- Prefer not to let `/api/get` block `/api/search`; run both concurrently if practical.
- Deduplicate LRCLIB results by LRCLIB id/service token before yielding.
- If `/api/get` and `/api/search` return the same LRCLIB item, emit one candidate and prefer the exact `/api/get` result for metadata/source-trace ties.
- If one LRCLIB path fails but the other yields or completes normally, keep the provider alive and report/yield what succeeded.
- Treat LRCLIB as failed only when all attempted LRCLIB paths fail before yielding usable candidates.

Provider-specific rich-timing improvements are explicitly deferred. QQMusic, NetEase, Kugou, or any future provider may return inline timing; LyricsX should prefer those results based only on parsed `LyricsLine.Attachments.InlineTimeTag` coverage, not provider identity.

## Domain model changes

Add a pure app-level evaluator/ranker in the local Swift package so it can be tested by package tests.

Required file/module placement for Phase 1:

```text
LyricsXPackage/Sources/LyricsXFoundation/Search/LyricsSearchMode.swift
LyricsXPackage/Sources/LyricsXFoundation/Search/LyricsCandidateEvaluation.swift
LyricsXPackage/Sources/LyricsXFoundation/Search/LyricsCandidateEvaluator.swift
LyricsXPackage/Sources/LyricsXFoundation/Search/LyricsCandidateRanker.swift
LyricsXPackage/Sources/LyricsXFoundation/Search/LyricsSyncKind.swift
LyricsXPackage/Tests/LyricsXFoundationTests/Search/LyricsCandidateEvaluatorTests.swift
LyricsXPackage/Tests/LyricsXFoundationTests/Search/LyricsCandidateRankerTests.swift
```

App-side adapters/integration belong in:

```text
LyricsX/Component/SearchSettings.swift
LyricsX/Component/LyricsSearchPipeline.swift
LyricsX/Component/LyricsSelector.swift
LyricsX/Component/LyricsSession.swift
LyricsX/Search/SearchLyricsViewModel.swift
LyricsX/Search/SearchLyricsView.swift
```

The package code must not depend on app target types such as `SearchSettings`, `DisplaySettings`, or `UserDefaults` wrappers.

### Search mode

Introduce an explicit search mode derived from user input:

```swift
enum LyricsSearchMode: Equatable {
    case titleAndArtist(title: String, artist: String)
    case titleOnly(title: String)
    case artistOnly(artist: String)
}
```

Rules:

- `title + artist`: strict song matching.
- `title only`: title correctness dominates; artist mismatch does not reject.
- `artist only`: artist correctness dominates; all songs by that artist may be valid.

### Candidate evaluation

Introduce a struct similar to:

```swift
struct LyricsCandidateEvaluation: Equatable {
    let mode: LyricsSearchMode
    let visibility: LyricsCandidateVisibility
    let matchTier: LyricsCandidateMatchTier
    let syncKind: LyricsSyncKind
    let titleScore: Double
    let artistScore: Double
    let durationScore: Double
    let albumScore: Double
    let overallScore: Double
    let rejectionReason: LyricsCandidateRejectionReason?
}
```

Potential enums:

```swift
enum LyricsCandidateVisibility: Equatable {
    case normal
    case looseFallback
    case unlikely
    case rejected
}

enum LyricsCandidateMatchTier: Equatable {
    case exactTitleArtist
    case strongTitleArtist
    case looseTitleArtist
    case titleOnly
    case exactArtistCatalog
    case looseArtistCatalog
    case rejected

    var titleBasedPriority: Int {
        switch self {
        case .exactTitleArtist: 600
        case .strongTitleArtist: 500
        case .titleOnly: 400
        case .looseTitleArtist: 300
        case .exactArtistCatalog: 200
        case .looseArtistCatalog: 100
        case .rejected: 0
        }
    }
}

enum LyricsSyncKind: Equatable {
    case karaoke
    case lineSynced
}
```

### Evaluator contract

Use a hybrid tier + deterministic score model.

The evaluator must first classify a candidate into a correctness tier, then compute deterministic 0–100 scores inside that tier. The tier decides validity; the numeric score only orders candidates within comparable tiers and powers the karaoke preference window.

Required public shape:

```swift
struct EvaluatedLyricsCandidate: Identifiable, Hashable {
    let lyrics: Lyrics
    let evaluation: LyricsCandidateEvaluation
    let arrivalIndex: Int

    var id: ObjectIdentifier { ObjectIdentifier(lyrics) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct LyricsCandidateEvaluator {
    func evaluate(
        lyrics: Lyrics,
        mode: LyricsSearchMode,
        requestedDuration: TimeInterval?,
        requestedAlbum: String?
    ) -> LyricsCandidateEvaluation
}

struct LyricsCandidateRankingConfiguration: Equatable {
    var sourcePriorityEnabled: Bool
    var sourcePriorityOrder: [String]
    var karaokePreferenceWindow: Double
    var nearEqualSourcePriorityWindow: Double
    var automaticLooseFallbackMinimumScore: Double
}
```

`LyricsCandidateRankingConfiguration` belongs with the pure evaluator/ranker in `LyricsXFoundation`. Do not make package-level ranking code depend on app-side `SearchSettings` or `UserDefaults`.

`LyricsX/Component/SearchSettings.swift` should expose a mapper such as:

```swift
extension SearchSettings {
    var rankingConfiguration: LyricsCandidateRankingConfiguration { ... }
}
```

This implementation may delete/deprecate old search-priority paths that become obsolete, including `LyricsSelector.hasHigherPriority(_:over:settings:)`, as long as behavior is replaced by the new evaluator/ranker architecture.

The evaluator must classify candidates without relying on source priority or karaoke preference:

1. `visibility` decides whether the candidate is normal, loose fallback, unlikely, or rejected.
2. `matchTier` describes why the candidate belongs to that visibility.
3. Rejected candidates are never eligible for automatic selection.
4. `overallScore` ranks candidates only after mode-specific tier comparison.
5. Duration is a tiebreaker after title/artist or artist-catalog tier; it must never make a wrong-title candidate valid.
6. Source priority is a later near-equal tiebreaker only in the collection ranker.

For `titleAndArtist` mode:

- exact normalized title + exact/strong artist relation → `exactTitleArtist`, normal, score 95–100.
- strong title variant + exact/strong artist relation → `strongTitleArtist`, normal, score 88–94.
- loose title overlap + exact/strong artist relation → `looseTitleArtist`, loose fallback, score 75–87.
- exact title + missing candidate artist → `strongTitleArtist`, normal, but capped below exact title+artist matches, score 88–92.
- strong title variant + missing candidate artist → `looseTitleArtist`, loose fallback, score 75–84.
- no meaningful title overlap → unlikely/rejected even when artist matches.

For `titleOnly` mode:

- exact normalized title → normal, score 95–100.
- strong title variant → normal, score 88–94.
- loose title overlap → loose fallback, score 75–87.
- no meaningful title overlap → unlikely/rejected.
- artist metadata can refine ties but cannot reject a matching title.

For `artistOnly` mode:

- exact primary artist token relation → `exactArtistCatalog`, normal artist-catalog result.
- strong non-primary artist relation, alias relation, or whole-phrase containment relation → `looseArtistCatalog`, normal artist-catalog result below exact-primary matches.
- missing or weak artist relation → unlikely.
- title is used for A–Z sorting, not for song correctness.
- the evaluator must not promote weak-artist candidates based on whether other normal artist results exist; that would require collection knowledge and belongs outside per-candidate evaluation.
- do not add an artist-only weak-artist fallback in this pass; weak-artist rows are visible only through the manual `Show unlikely results` toggle.

Examples:

- query `Olivia Rodrigo`, candidate artist `Olivia Rodrigo` → `exactArtistCatalog`.
- query `Olivia Rodrigo`, candidate artist `Olivia Rodrigo feat. X` → `exactArtistCatalog` when the primary token is Olivia Rodrigo.
- query `Olivia Rodrigo`, candidate artist `X feat. Olivia Rodrigo` → `looseArtistCatalog`.
- query `Olivia Rodrigo`, candidate artist `Oliver Rodigan` → unlikely.

Artist relation must handle common multi-artist forms before scoring:

- split candidate and requested artists on separators such as `,`, `、`, `&`, `and`, `feat.`, `ft.`, `featuring`, `with`, `/`, and `x` when used as a collaboration separator;
- normalize each artist token using the same text normalization rules;
- define the primary artist token as the first normalized token before any collaboration/feature separator;
- for symmetric separators such as `,`, `、`, `&`, `and`, `/`, and collaboration `x`, treat the first listed artist as primary for ranking;
- for feature separators such as `feat.`, `ft.`, `featuring`, and `with`, tokens after the separator are non-primary featured artists;
- treat the relation as strong when any normalized artist token exactly matches, or when one full normalized artist string contains the other as a whole artist/token phrase;
- exact primary-token matches outrank exact non-primary-token matches;
- in `titleAndArtist` mode, an exact non-primary artist match can still be a strong artist relation, but it must be capped below an exact primary artist match;
- in `artistOnly` mode, exact primary-token match maps to `exactArtistCatalog`; exact non-primary-token match maps to `looseArtistCatalog`;
- do not let a featured artist alone outrank an exact primary artist match when both exist.

Duration scoring is a tiebreaker only:

- exact/near duration within 2 seconds → strongest duration tiebreak;
- within 10 seconds → weaker positive tiebreak;
- missing duration on either side → neutral;
- larger mismatch → negative tiebreak inside the same tier only.

Album scoring is a tiebreaker only:

- exact normalized album match → positive tiebreak inside the same correctness tier;
- missing album on either side → neutral;
- album mismatch → weak negative tiebreak inside the same tier only;
- album must never make a wrong-title or wrong-artist candidate valid.

### Normalization role

Normalization is preprocessing only, not the entire matching policy.

It should handle practical comparability:

- lowercase,
- trim whitespace,
- fold diacritics,
- normalize apostrophes/dashes/quotes,
- collapse punctuation to spaces,
- tokenize words,
- optionally strip common version markers for a secondary “core title” comparison.

It must not make arbitrary titles equivalent.

Examples:

- `lacy` vs `lacy` → exact.
- `lacy` vs `lacy - acoustic` → strong/variant.
- `lacy` vs `lacy the redemption` → loose title overlap.
- `lacy` vs `drivers license` → rejected for title+artist and title-only modes.

### Sync detection

Add a reusable computed property/helper:

```swift
extension Lyrics {
    var syncKind: LyricsSyncKind { ... }
    var isKaraokeTimed: Bool { ... }
}
```

Recommended classification:

- consider only enabled, non-empty lyric lines,
- karaoke if at least 2 eligible lines have `line.attachments.timetag`, and
- at least 50% of eligible lines have timetag attachments.

Everything else is `.lineSynced`.

This prevents one stray `[tt]` line from marking a whole result as karaoke.

## Ranking and collection rules

### Collection ranker

Use a separate collection ranker in addition to the per-candidate evaluator.

Required shape:

```swift
struct LyricsCandidateRanker {
    func rankedCandidates(
        _ candidates: [EvaluatedLyricsCandidate],
        mode: LyricsSearchMode,
        configuration: LyricsCandidateRankingConfiguration
    ) -> [EvaluatedLyricsCandidate]

    func bestCandidate(
        from candidates: [EvaluatedLyricsCandidate],
        mode: LyricsSearchMode,
        configuration: LyricsCandidateRankingConfiguration
    ) -> EvaluatedLyricsCandidate?
}
```

The evaluator scores one candidate. The ranker owns set-level rules:

- karaoke preference window,
- loose fallback only when exact/strong candidates are absent,
- source priority near-equal tiebreaking,
- provider/arrival order final tiebreaking,
- artist-only title A–Z ordering.

Avoid implementing these set-level rules as a pairwise-only comparator; karaoke threshold and loose fallback depend on knowing the best candidates in the collection.

### Universal order for title-based searches

For `titleAndArtist` and `titleOnly` searches, normal ranking must be:

1. candidate not rejected,
2. explicit `matchTier.titleBasedPriority` / correctness,
3. overall match score,
4. karaoke preference threshold,
5. duration score,
6. source priority only among near-equal candidates,
7. provider/search arrival order as final stable tiebreaker.

Wrong-title candidates are not normal results.

### Artist-only order

For `artistOnly` searches, do not use `matchTier.titleBasedPriority`. Artist-only search is a catalog browse mode, so title tiers are irrelevant.

Artist-only ranking must be:

1. candidate not rejected,
2. artist-catalog tier (`exactArtistCatalog` before `looseArtistCatalog`),
3. visibility (`normal` before `unlikely`; `looseFallback` is not used for artist-catalog matches),
4. normalized title A–Z,
5. karaoke preference only within the same normalized title group,
6. source priority only among near-equal duplicate/same-title candidates,
7. provider/search arrival order as final stable tiebreaker.

Missing-title candidates sort after titled candidates inside the same artist tier. Wrong-artist candidates are not normal artist-only results.

### Karaoke threshold

Use a configurable constant in code, initially:

```swift
let karaokePreferenceWindow = 10.0
```

Meaning:

> A karaoke result may beat the best line-synced result only if its overall score is within 10 points of that line-synced result.

Examples:

- line-synced `lacy / Olivia Rodrigo`, score 100
- karaoke `lacy / Olivia Rodrigo`, score 96
- choose karaoke

But:

- line-synced `lacy / Olivia Rodrigo`, score 100
- karaoke `lacy the redemption / Olivia Rodrigo`, score 82
- choose line-synced

Rejected candidates never become eligible because they are karaoke.

### Source identity and source priority

Existing source priority remains useful, but only as a near-equal tiebreaker.

All source-priority comparisons must use one canonical source identity:

- `LyricsProviders.ProviderDescriptor.source` is the canonical source display name and ranking key.
- `LyricsProviders.ProviderEvent.source` must echo the descriptor source exactly.
- `LyricsSearchPipeline` must set or overwrite `lyrics.metadata.service = source` when mapping a provider candidate event, before preparation/evaluation emits the app-level candidate.
- `availableLyricsSources` / `SearchSettings.sourcePriorityOrder` must be derived from the same descriptor construction used by `LyricsSearchPipeline`, so preferences and emitted remote candidates use the same source names.
- Synthetic local source names (`Embedded`, `Beside Track`, `Local Storage`) are displayed for local lyrics and local-upgrade diagnostics, but are not included in source-priority preferences and cannot participate in remote source-priority replacement.
- The manual Source column should display `lyrics.metadata.service` after this canonicalization.
- The ranker may compare normalized source keys internally, but it must preserve canonical display names in models/UI.
- Unknown or missing source names sort after known configured sources and must not beat known sources through source-priority logic.

This avoids silent priority failures caused by provider spelling/casing differences.

Source priority must not allow:

```text
drivers license / Olivia Rodrigo / preferred source
```

to beat:

```text
lacy / Olivia Rodrigo / lower-priority source
```

Recommended implementation:

- compute evaluation first,
- compare explicit title-based match tier priority and score first for title-based searches,
- compare artist-catalog tier and normalized title group first for artist-only searches,
- apply source priority only when candidates are within a small near-equal score window, e.g. 2 points, and same visibility/tier/sync decision,
- apply this same near-equal source-priority rule to automatic selection and manual result ordering.

### `Lyrics.quality`

Do not use `Lyrics.quality` as the primary rank.

If retained at all, use it as a low-priority signal only after guarding:

```swift
let safeQuality = lyrics.quality.isFinite ? lyrics.quality : 0
```

## Manual search behavior

### Search modes

Change `SearchLyricsViewModel.canSearch` to allow title-only or artist-only search:

```swift
!title.trimmed.isEmpty || !artist.trimmed.isEmpty
```

Build request/search mode from trimmed fields:

- both fields non-empty → `.titleAndArtist`
- title only → `.titleOnly`
- artist only → `.artistOnly`

Provider request construction must use LyricsKit’s existing `LyricsSearchRequest.SearchTerm` as follows:

- title+artist → `.info(title: title, artist: artist)`
- title-only → `.keyword(title)`
- artist-only → `.keyword(artist)`

Do not send `.info` requests with empty title or artist fields for manual partial-input searches. The evaluator/ranker is responsible for interpreting the returned candidates according to the explicit `LyricsSearchMode`.

Manual search may run with no current track. In that case, request duration is `nil` for evaluator scoring and `0` when constructing `LyricsSearchRequest` because the LyricsKit request type requires a concrete `TimeInterval`.

### Result visibility

For title+artist and title-only searches:

- normal list shows exact/strong matches,
- loose title-overlap matches show only when exact/strong matches are exhausted,
- unlikely matches are hidden by default behind the `Show unlikely results` toggle,
- rejected matches are never displayed or selectable,
- show a small `Show unlikely results` toggle when any unlikely candidates were collected.

For artist-only searches:

- songs by the searched artist are valid,
- exact artist match first,
- sort title A–Z,
- karaoke is used within duplicate/same-title groups,
- provider relevance/source priority remain lower tiebreakers.

### Duplicate-looking results

Keep separate rows for each source in this pass.

Do not introduce expandable grouping yet.

Sort best duplicate first and make source + mic indicator clear.

### Mic indicator

Add a small mic symbol in manual search results for karaoke candidates.

Acceptable UI:

- a leading `🎤` column,
- or an SF Symbol `mic.fill`, if available and visually consistent.

The user-approved requirement is simply: show the mic symbol for karaoke.

### Search status model

Add explicit search status to `SearchLyricsViewModel`:

```swift
enum SearchStatus: Equatable {
    case idle
    case searching(summary: String)
    case foundVisible(count: Int, hiddenUnlikely: Int, rejected: Int)
    case noMatches(hiddenUnlikely: Int, rejected: Int)
    case failed(message: String, visibleCount: Int, hiddenUnlikely: Int, rejected: Int)
    case timedOut(visibleCount: Int, hiddenUnlikely: Int, rejected: Int)
    case cancelled(visibleCount: Int, hiddenUnlikely: Int, rejected: Int)
}
```

Exact shape can change, but it must support:

- provider summary status,
- visible result counts, including normal rows and currently visible loose-fallback rows,
- hidden-unlikely count for user-facing copy and toggle count,
- rejected count for diagnostics/internal status accounting only,
- failure/cancel/timeout/no-match states.

### Apply behavior

Manual `Apply` is an explicit user override.

Behavior:

- Applying a manual result cancels any in-flight automatic search for the current track.
- Automatic finalization/export must not replace a user-selected result.
- `Apply` is enabled only when a visible row is selected and `player.currentTrack` exists.
- When no current track exists, `Apply` is disabled with no extra inline copy or tooltip requirement.
- Applying any visible row keeps current semantics: unblock the current track and album, call `session.select(...)`, and auto-export to Apple Music if the existing auto-export preference is enabled.
- Unlikely rows require the `Show unlikely results` toggle before they can become visible; once visible, applying them does not require an additional confirmation in this pass.
- Applying a hidden row is impossible; if the unlikely toggle is turned off while an unlikely row is selected, clear selection/preview/artwork before Apply can run.

### Search button, keyboard, and status behavior

Status placement:

- show one compact status line under the title/artist/search row and above the results table;
- use secondary text color for neutral/searching states;
- use warning/error color only for failed or timed-out states;
- keep status visible while partial results are shown.

When no search is running:

- button says `Search`.

When search is running and fields are unchanged from the active search:

- button says `Cancel`.
- action cancels the active search.

When search is running and fields changed since the active search started:

- button says `Search Again`.
- editing fields alone does not clear current partial results.
- action cancels current search, clears old results/selection/preview/artwork, resets the unlikely toggle, and starts a new search with current fields.

Keyboard behavior:

- pressing Return in either search field starts search when idle;
- pressing Return in either search field starts `Search Again` when fields changed during an active search;
- pressing Return while searching with unchanged fields does not cancel search;
- plain Return must not apply lyrics;
- pressing Escape cancels the active search when searching;
- `Command-Return` applies the selected visible row when `Apply` is enabled;
- double-clicking a visible result row keeps existing behavior and applies it when `Apply` is enabled.

Opening Search Lyrics from the menu bar should continue to auto-search the current track immediately, but the UI must visibly show that the search is active.

### Provider feedback

The user-approved target is provider summary status, not a detailed log.

Examples:

- `Searching QQMusic…`
- `Searching NetEase…`
- `Found 3 likely matches`
- `4 likely matches · 7 unlikely hidden`
- `Kugou failed · showing 2 partial matches`
- `No matching lyrics found · 5 unlikely hidden`

For user-facing copy, “likely matches” means the rows currently visible without the unlikely toggle: normal rows, or loose-fallback rows when loose fallback is active because no exact/strong rows exist.

Implement provider summary status with a first-class event stream. Do not infer provider status from raw candidates.

The preferred design is cross-repo:

- LyricsKit exposes raw provider events and keeps its existing `lyrics(for:)` API as a convenience wrapper.
- LyricsX maps LyricsKit raw provider events into app-level evaluated search events after candidate preparation and evaluation.

Required LyricsKit event API shape:

```swift
extension LyricsProviders {
    public struct ProviderDescriptor: Sendable {
        /// Canonical source display name and source-priority ranking key.
        public let source: String
        public let provider: LyricsProvider
    }

    public enum ProviderEvent {
        case providerStarted(source: String, request: LyricsSearchRequest)
        case candidate(source: String, lyrics: Lyrics)
        case providerFinished(source: String, request: LyricsSearchRequest, yieldedCount: Int)
        case providerFailed(source: String, request: LyricsSearchRequest, message: String, yieldedCount: Int)
        case completed
    }
}

extension LyricsProviders.Group {
    public func events(for request: LyricsSearchRequest) -> AsyncStream<LyricsProviders.ProviderEvent>
}
```

Provider failures are represented as `providerFailed` event values. `completed` is emitted only after all provider and plugin-derived work finishes normally. Cancellation ends the stream without emitting `completed`. The app-level `LyricsSearchPipeline.events(...)` stream should also be non-throwing; current candidate preparation is non-throwing, and any future per-candidate preparation failure should be represented as an event value rather than terminating partial results.

Required app-level event API on `LyricsSearchPipeline`:

```swift
enum LyricsSearchEvent {
    case providerStarted(source: String)
    case candidate(EvaluatedLyricsCandidate)
    case providerFinished(source: String, yieldedCount: Int)
    case providerFailed(source: String, message: String, yieldedCount: Int)
    case completed
}

func events(
    for request: LyricsSearchRequest,
    mode: LyricsSearchMode,
    requestedDuration: TimeInterval?,
    requestedAlbum: String?
) -> AsyncStream<LyricsSearchEvent>
```

Implementation requirements:

- LyricsKit event emission should live on `LyricsProviders.Group`; individual providers should not need a new event protocol in this pass.
- LyricsKit `Group.events(for:)` should be non-throwing: `AsyncStream<LyricsProviders.ProviderEvent>`.
- LyricsKit should own provider descriptors/source identity for provider event emission.
- LyricsKit provider events should echo the descriptor `source` exactly; providers should not invent event source names.
- LyricsKit should run providers concurrently so one slow source does not block later sources.
- LyricsKit should emit provider started, raw candidate yielded, provider finished, provider failed, and completed events.
- LyricsKit should keep other providers running when one provider fails.
- LyricsKit should cancel child provider work when the event stream is cancelled.
- LyricsKit should not emit `completed` after cancellation.
- LyricsX should set `lyrics.metadata.service` from the raw provider event `source`, then prepare and evaluate each raw lyric after receiving the raw candidate event.
- LyricsX should emit `candidate` for every fetched, prepared, and evaluated lyrics candidate, including candidates whose evaluation is `.unlikely` or `.rejected`.
- LyricsX should assign `arrivalIndex` at the pipeline boundary in the order candidates are yielded to the app stream.
- LyricsX should emit `completed` only after all provider tasks finish normally.
- LyricsX should not emit `completed` after cancellation or deadline termination; the consumer owns cancelled/timed-out status.
- After stream cancellation or automatic deadline termination, LyricsX should emit no further provider or candidate events.
- Manual search should consume events directly and store all evaluated candidates for status/counting.
- For title+artist/title-only manual searches, show normal exact/strong rows by default when any exist; show loose-fallback rows by default only when no normal rows exist.
- For artist-only manual searches, use artist-only ranking rules instead of title-based loose-fallback suppression.
- Manual search should show `.unlikely` candidates only when `Show unlikely results` is enabled, and never show `.rejected` candidates.
- Automatic search may consume the same event stream and ignore provider status events, or use a candidate-only convenience wrapper built on top of `events(for:)`. Automatic search must ignore `.unlikely` and `.rejected` candidates except for the explicitly defined loose fallback policy, which applies only to `.looseFallback` candidates above the automatic fallback threshold.

## Automatic search behavior

Automatic search must use the same evaluator and ranking rules as manual search.

### Strong matches

For current track title+artist, automatic search should auto-select the best normal candidate according to evaluator + collection-ranker ranking.

### Automatic collection lifecycle

Automatic search should remain responsive while still giving slower karaoke-capable providers a chance to win.

Behavior:

1. Start remote search for the current track.
2. Evaluate every incoming candidate.
3. When the first strong acceptable candidate arrives, display it immediately as an interim `currentLyrics`.
4. Continue collecting candidates until either:
   - all providers finish, or
   - a 15 second automatic search deadline elapses.
5. Whenever the collection ranker finds a better candidate than the currently displayed interim result, replace `currentLyrics`.
6. Ignore candidates that arrive after cancellation, track change, manual clear, manual apply/select, or the automatic deadline.
7. Interim automatic results are display-only for persistence/export purposes.
8. If Apple Music auto-export is enabled, export only after provider completion or the 15 second deadline, using the final best candidate.
9. After provider completion or the 15 second deadline, persist the final selected lyrics to disk when `metadata.needsPersist == true`.
10. Manual `select(...)` / Apply cancels any in-flight automatic search and becomes final immediately; automatic finalization/export must not replace it.

This replaces the current “accept first, then collect for `SearchSettings.priorityWindow` seconds” behavior for automatic search. `SearchSettings.priorityWindow` may be removed from this flow or left unused for backward compatibility; do not let it conflict with the new 15 second deadline.

Persistence/export requirements:

- Do not auto-export interim automatic results before search finalization.
- Persist the final dirty remote result after automatic search finalization so karaoke upgrades are durable even before the next track change.
- When a remote final result replaces local line-synced lyrics, save it through the normal app storage persistence path; do not overwrite the original local file path directly.
- Existing user-provided beside-track/imported local files must not be destructively rewritten by automatic karaoke upgrade.

### Loose fallback

Automatic search may select a loose title-overlap result only when:

- there are no current/local lyrics, and
- no exact/strong remote candidate exists, and
- the loose candidate score is above a conservative threshold.

Initial threshold recommendation:

```swift
let automaticLooseFallbackMinimumScore = 80.0
```

This should be easy to tune.

### Local lyrics upgrade policy

User-approved behavior:

- Keep local karaoke/word-timed lyrics.
- If local lyrics are line-synced, show them immediately and continue network search for a clearly better remote result.
- A strong karaoke result may replace local line-synced lyrics when it satisfies the karaoke threshold.
- A strong line-synced remote result may replace local line-synced lyrics only when it is materially better, such as a better duration/album match.
- Do not replace local line-synced lyrics with a weak or loose remote result.

Local lyrics should still be evaluated with the same evaluator so local-upgrade comparisons are explicit and testable. Assign synthetic canonical source names before evaluation:

- `Embedded` for embedded track lyrics,
- `Beside Track` for beside-track `.lrcx` / `.lrc`,
- `Local Storage` for saved-path `.lrcx` / `.lrc`.

These local source names are for display and diagnostics. Source priority must not make a remote result replace local lyrics; local replacement is governed only by the local-upgrade policy above.

Implementation consequence:

`LocalLyricsLoader.Result.found` may need more nuance than complete vs partial. Current behavior stops network search for complete local `.lrcx` or beside-track lyrics. The new behavior needs to know whether the loaded local result is karaoke timed.

Possible implementation options:

1. Keep `LocalLyricsLoader.Result` shape and decide in `LyricsSession` after receiving `.found(let lyrics)` whether to continue searching based on `lyrics.isKaraokeTimed`.
2. Extend result type to include upgrade policy metadata.

Prefer option 1 for a surgical first pass.

Pseudo-flow:

```swift
switch LocalLyricsLoader.load(...) {
case .found(let lyrics):
    currentLyrics = lyrics
    if lyrics.isKaraokeTimed {
        return
    }
    // Continue network search, but only accept clearly better strong remote results.
case .foundPartial(let lyrics):
    currentLyrics = lyrics
    // Continue existing search behavior.
case .none:
    break
}
```

Then automatic remote acceptance needs a mode/policy:

```swift
enum AutomaticAcceptancePolicy {
    case normal
    case localUpgradeOnly(existing: Lyrics)
}
```

For `.localUpgradeOnly`:

- candidate must be exact/strong for the current title+artist,
- rejected, unlikely, and loose-fallback candidates cannot replace local lyrics,
- karaoke candidates may replace local line-synced lyrics when they satisfy the karaoke threshold compared to the existing local lyrics,
- line-synced remote candidates may replace local line-synced lyrics only when their evaluated score is materially higher than the evaluated local lyrics, initially by at least 5 points,
- duration and album matches can contribute to that material improvement,
- source priority cannot override this.

## Pipeline/workflow changes

### Candidate preparation

Keep `LyricsSearchPipeline` as the owner of provider group, preparation, and streaming.

Add candidate evaluation after preparation, not before, because metadata and filtered lines may affect sync kind.

Potential API shape:

```swift
func candidates(for request: LyricsSearchRequest, policy: LyricsSearchCandidatePolicy) -> AsyncStream<EvaluatedLyricsCandidate>
```

Where:

```swift
struct EvaluatedLyricsCandidate {
    let lyrics: Lyrics
    let evaluation: LyricsCandidateEvaluation
    let arrivalIndex: Int
}
```

Use the app-level event API as the clean design:

- pipeline fetches raw candidates from LyricsKit provider events,
- pipeline prepares candidates,
- pipeline evaluates candidates with request context and emits `LyricsSearchEvent.candidate`,
- selector/ranker only ranks and filters already evaluated candidates.

### Selector changes

Replace or augment:

```swift
LyricsSelector.hasHigherPriority(_:over:settings:)
LyricsSelector.insert(_:into:settings:)
```

with evaluator-aware APIs.

Possible shape:

```swift
func hasHigherPriority(
    _ candidate: EvaluatedLyricsCandidate,
    over current: EvaluatedLyricsCandidate?,
    settings: SearchSettings
) -> Bool
```

Manual search can store evaluated results instead of raw `Lyrics`.

Automatic search can track current evaluation alongside `currentLyrics` inside the search task.

Avoid storing evaluation permanently in `Lyrics.Metadata` unless needed; ranking is request-dependent.

## UI surface changes

### Search result row model

Current `LyricsResult` wraps only `Lyrics`.

Extend it or introduce a new row model:

```swift
struct LyricsResult: Identifiable, Hashable {
    let lyrics: Lyrics
    let evaluation: LyricsCandidateEvaluation
    let isUnlikely: Bool
    var syncIcon: String { evaluation.syncKind == .karaoke ? "🎤" : "" }
}
```

Keep object identity by `ObjectIdentifier(lyrics)` unless evaluated wrapping changes require a stable generated id.

### Search table

Add mic indicator column or leading title decoration.

Recommended minimal table:

```text
🎤 | Title | Artist | Source
```

Line-synced rows can have an empty mic column.

### Unlikely results toggle

When unlikely candidates exist, show a `Show unlikely results (N)` toggle below the results table and above the footer. Rejected candidates never create the toggle by themselves.

Behavior:

- toggle is hidden when there are zero unlikely candidates;
- default state is off for each new search;
- when enabled, unlikely rows are appended below the currently visible likely/loose rows in the same table;
- unlikely rows are visually dimmed using secondary foreground/opacity treatment;
- do not add an `Unlikely` text badge unless a later design pass asks for it;
- unlikely rows remain selectable, previewable, draggable, and applicable, because the toggle is an intentional manual override;
- when the toggle is turned off while an unlikely row is selected, clear `selectionID`, `preview`, and `artwork`;
- `Apply` must never target a row that is currently hidden.

### Empty/loading/error states

Replace ambiguous empty text with status-aware messages:

- idle with empty fields: `Enter a title, artist, or both to search`
- searching: show current provider/coarse status
- no normal matches but unlikely hidden: `No likely matches found` plus `Show unlikely results (N)` where `N` is hidden-unlikely count only
- failure with partial results: show partials and status text
- total failure: `Search failed. Check your connection and try again.`

Do not block or visually override manual search just because no track is playing. Manual search is valid as lookup/browsing even with no current track. Search, preview, and drag/export remain available. `Apply` remains disabled when there is no current track because there is no track to attach the selected lyrics to.

## Edge cases and decided behaviors

### `lacy / Olivia Rodrigo`

Normal results:

- `lacy / Olivia Rodrigo` → exact/strong, shown.
- `lacy - acoustic / Olivia Rodrigo` → strong/variant, shown below exact.
- `lacy the redemption / Olivia Rodrigo` → loose title-overlap, shown only if no exact/strong results exist.
- `drivers license / Olivia Rodrigo` → rejected/unlikely, hidden behind toggle.
- `drop dead / Olivia Rodrigo` → rejected/unlikely, hidden behind toggle.

### Short one-word titles

For short one-word title queries, require whole-token overlap for loose matching.

Examples for query `lacy`:

- `lacy the redemption` → loose.
- `drivers license` → rejected.
- `lazy` → rejected unless future fuzzy mode is explicitly introduced.
- `lady` → rejected unless future fuzzy mode is explicitly introduced.

### Artist-only `Olivia Rodrigo`

Normal results can include multiple songs.

Ordering:

1. exact artist matches,
2. title A–Z,
3. karaoke first within same title/duplicate group,
4. source/provider tiebreakers.

### Title-only `lacy`

Results with matching title are valid even if artist differs.

Ordering:

1. exact/strong title,
2. karaoke threshold,
3. artist closeness if available only as a tiebreaker,
4. source/provider tiebreakers.

### Rejected result access

Manual search never displays `.rejected` candidates. The `Show unlikely results` toggle reveals only `.unlikely` candidates.

Rejected candidates may count toward diagnostics/internal status accounting if useful, but user-facing toggle/copy should use hidden-unlikely counts. Rejected candidates are not selectable, previewable, draggable, applicable, or sufficient to create the toggle by themselves.

Automatic search never selects rejected candidates.

### Provider failures

Search should keep partial successful results.

Manual status should indicate failure/coarse provider issue where possible.

Automatic search should not clear already-loaded local/current lyrics just because later provider work fails.

### Cancellation

Cancelling manual search should stop the task and keep partial normal results visible.

Status should become `Cancelled · showing N results` or equivalent.

Starting a new manual search clears old results, selection, preview, artwork, unlikely toggle state, and status for the new request. Editing fields during an active search does not clear current partial results until `Search Again` is triggered.

### Timeouts

Automatic and manual search use separate deadlines.

Automatic search:

- 15 second deadline;
- owned by `LyricsSession`;
- `LyricsSearchPipeline` and LyricsKit do not enforce this app-level deadline;
- on deadline, cancel the automatic event stream, finalize the current best candidate once, and persist/export only if the search is still current.

Manual search:

- 30 second whole-search timeout;
- owned by `SearchLyricsViewModel`;
- on timeout, cancel the provider event stream;
- keep partial visible results;
- status explains that search timed out and user can retry;
- button returns to `Search`.

Per-provider timeouts are deferred for this pass.

## Testing strategy

Testing expansion is a final hardening phase after the full implementation is wired. During implementation, still verify each phase with the smallest relevant build/typecheck/manual check so regressions are caught early.

There are no app-wide automated tests configured in the Xcode scheme, but `LyricsXPackage` and LyricsKit both have Swift package test targets. Prefer pure evaluator placement that allows package-level tests.

Required LyricsXFoundation evaluator/ranker cases:

1. Exact title+artist beats wrong title same artist.
2. Wrong title same artist is rejected for title+artist search.
3. `lacy the redemption` is loose, not exact, for `lacy`.
4. Loose title-overlap shows only when strong results are absent.
5. Karaoke within 10 points beats line-synced.
6. Karaoke below the threshold does not beat a stronger line-synced result.
7. Source priority applies to automatic and manual ordering only for near-equal candidates.
8. Source priority cannot make rejected/wrong-title result win.
9. Non-finite `Lyrics.quality` is ignored or safely handled.
10. Artist-only search accepts multiple titles by the artist.
11. Artist-only results sort title A–Z, karaoke within same title.
12. Title-only search does not reject artist mismatch.
13. Karaoke detection requires enough `[tt]` lines and ignores one stray timetag.
14. Album match helps only as a tiebreaker.
15. Album mismatch cannot make a wrong song valid.
16. Local karaoke is not replaced by remote results.
17. Local line-synced lyrics can be replaced by strong karaoke within threshold.
18. Local line-synced lyrics can be replaced by materially better line-synced results.
19. Loose/weak remote results cannot replace local lyrics.
20. App-level correctness tests do not depend on `Lyrics.isMatched()`.

Required LyricsKit provider-event/LRCLIB cases:

1. `LyricsProviders.Group.events(for:)` emits provider started, candidate, provider finished, and completed events.
2. A provider failure emits `providerFailed` and does not stop other providers.
3. Cancelling the event stream does not emit `completed`.
4. `lyrics(for:)` remains a candidate-only compatibility wrapper over events.
5. LRCLIB keeps `/api/search` for all searches.
6. LRCLIB also runs `/api/get` when title, artist, album, and duration are available.
7. LRCLIB deduplicates exact/broad duplicate results by id/service token, with exact `/api/get` results winning metadata/source-trace ties.
8. LRCLIB reports provider failure only when all attempted LRCLIB paths fail before yielding usable candidates.

## Phased rollout

### Phase 0 — LyricsKit provider-event prerequisite

Separate repo: `/Users/f/Core/dev/projects/LyricsKit`.

- Add a raw non-throwing provider event stream API on `LyricsProviders.Group` while preserving `lyrics(for:)`.
- Keep individual provider APIs unchanged in this pass.
- Add explicit provider descriptors to `LyricsProviders.Group` for source-name ownership; provider events must echo descriptor source names exactly.
- Emit failures as `providerFailed` event values, not thrown stream errors.
- Preserve concurrent provider search and cancellation behavior.
- Add group-level provider-event tests for started/candidate/finished/failed/completed events and cancellation where feasible.
- Add `LyricsSearchRequest.UserInfoKey.albumName` and `LyricsSearchRequest.albumName`.
- Add LRCLIB `/api/get` exact lookup for complete title+artist+album+duration requests while still running the existing `/api/search` path; deduplicate results by LRCLIB id/service token.
- Do not add Musixmatch-specific richsync work.

### Phase 0.5 — LyricsX local LyricsKit integration

- Point LyricsX at the local LyricsKit checkout for development.
- Update `LyricsXPackage/Package.swift` to use the local LyricsKit checkout by default for this work, or document the required `LYRICSX_USE_LOCAL_DEPENDENCY=1` build/test environment if keeping the existing toggle.
- Update Xcode SPM/package resolution so LyricsX builds against the local LyricsKit API during implementation.
- Update `LyricsX/Component/LyricsSearchPipeline.swift` provider construction from the old `LyricsProviders.Service.noAuthenticationRequiredServices` / `LyricsProviders.Musixmatch(usertoken:)` API to the current local LyricsKit service API.
- Update `LyricsX/Component/LyricsSelector.swift` source list construction from `LyricsProviders.Service.allCases` to `LyricsProviders.ServiceID.allCases`.
- Build provider descriptors through LyricsKit service IDs/options and use the same descriptor source list for `availableLyricsSources` / source-priority normalization.
- Continue supporting the existing Musixmatch token preference as ordinary provider configuration.
- When the Musixmatch token is absent, keep Musixmatch out of the active descriptor list and out of normalized source-priority options; when the token becomes available, append/normalize it like any newly available source.
- Pass album metadata through `LyricsSearchRequest.UserInfoKey.albumName` only for automatic current-track searches when album is available; do not include album for manual search requests.
- Keep `LyricsSearchPipeline.candidates(for:strict:)` working only as a short-lived compatibility path until evaluator/ranker event wiring replaces it.
- Remove the strict-search preference and old `Lyrics.isMatched()` filtering once evaluator/ranker wiring starts.

Expected provider API and strict-search cleanup targets:

```text
LyricsX/Component/LyricsSearchPipeline.swift
LyricsX/Component/LyricsSelector.swift
LyricsX/Component/SearchSettings.swift
LyricsX/Component/AppContainer.swift
LyricsX/Preferences/GeneralPreferencesView.swift
LyricsX/Utility/UserDefaultsKeys.swift
LyricsXPackage/Package.swift
LyricsX.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

Current known old-API usages:

```swift
LyricsProviders.Service.noAuthenticationRequiredServices
LyricsProviders.Service.allCases
LyricsProviders.Musixmatch(usertoken: token)
```

Target local LyricsKit API concepts:

```swift
LyricsProviders.ServiceID.allCases
LyricsProviders.Service.qq.create(httpClient:)
LyricsProviders.Service.netease.create(httpClient:)
LyricsProviders.Service.kugou.create(httpClient:)
LyricsProviders.Service.lrclib.create(httpClient:)
LyricsProviders.Service.musixmatch.create(.init(usertoken: token), httpClient:)
LyricsProviders.ProviderDescriptor(source:provider:)
LyricsProviders.Group(descriptors:plugins:)
```

Implementation order decision:

- Complete LyricsKit Phase 0 before wiring evaluator/ranker into LyricsX search.
- Complete LyricsX Phase 0.5 before changing manual or automatic ranking behavior.
- Keep the pure evaluator/ranker independent of LyricsKit provider events; it should depend only on `Lyrics`, search mode, requested duration, and ranking configuration.

### Phase 1 — Pure evaluator

- Add search mode model.
- Add normalization/tokenization helpers.
- Add sync kind detection.
- Add candidate evaluator.

No UI or search behavior changes yet. Full automated test expansion is deferred to the final hardening phase, but each slice should still be build/typecheck verified.

### Phase 2 — Manual search filtering/ranking

- Remove/deprecate `SearchSettings.strictSearchEnabled`, the General preferences `Strict search` toggle, and `LyricsSearchPipeline`'s `strict`/`Lyrics.isMatched()` filtering path.
- Store evaluated candidates in `SearchLyricsViewModel`.
- Apply source priority to manual ordering only through the ranker's near-equal tiebreaker rule.
- Allow title-only and artist-only search.
- Filter normal vs unlikely results.
- Sort title-based and artist-only modes according to decided rules.
- Keep separate duplicate/source rows.

### Phase 3 — Manual UI indicators and unlikely toggle

- Add mic symbol column/decorator.
- Add `Show unlikely results` toggle when filtered results exist.
- Update empty/no-match copy.

### Phase 4 — Automatic search integration

- Use evaluator in `LyricsSession` automatic acceptance.
- Apply karaoke threshold.
- Apply source priority only as near-equal tiebreaker, matching manual result ordering.
- Add loose fallback policy.
- Add local line-synced to clearly better remote upgrade behavior, including karaoke upgrades and materially better line-synced matches.
- Implement the 15 second automatic deadline in `LyricsSession`, not in LyricsKit or `LyricsSearchPipeline`.
- Ensure manual `select(...)` / Apply cancels in-flight automatic search and prevents later automatic finalization/export from replacing the user-selected result.

### Phase 5 — Manual search feedback/cancel/search-again

- Add explicit `SearchStatus`.
- Keep auto-search-on-open behavior.
- Implement button states: Search / Cancel / Search Again.
- Implement the 30 second whole-search manual timeout in `SearchLyricsViewModel`.
- Keep partial results visible on cancel/failure/timeout.
- Add provider summary/coarse status.

### Phase 6 — Provider status refinement

- Tune provider summary status based on the LyricsKit event stream.
- Tune scoring thresholds with real examples.
- Defer per-provider timeout behavior unless whole-search manual timeout proves insufficient.
- Defer provider-specific rich-timing improvements unless a concrete provider gap is found after ranking integration.

### Phase 7 — Final automated test hardening

- Add the required LyricsXFoundation evaluator/ranker tests.
- Add the required LyricsKit provider-event and LRCLIB tests.
- Run the relevant package tests and app build checks.
- Fix implementation defects found by tests; do not weaken tests to match broken behavior.

## Resolved decisions

- Shared evaluator/ranker for automatic and manual search: yes.
- Automatic search should prefer karaoke too: yes, within threshold.
- Karaoke threshold: reasonably close, initial 10 score points.
- Manual mic indicator: simple mic symbol.
- Wrong song candidates: filter from normal title-based results.
- Loose title-overlap: for title+artist/title-only searches, show only when exact/strong matches are absent; do not append loose rows below normal rows in the first pass.
- Automatic loose fallback: only if no current/local lyrics and score is conservative enough.
- Local lyrics upgrade: keep local karaoke; when local lyrics are line-synced, allow only exact/strong remote results to replace them, either via karaoke threshold or a materially better line-synced score from duration/album evidence; evaluate local lyrics with synthetic sources `Embedded`, `Beside Track`, and `Local Storage` for explicit upgrade comparisons.
- Manual apply/select: cancels in-flight automatic search and becomes final; automatic finalization/export must not replace user choice.
- Automatic deadline: 15 seconds, owned by `LyricsSession`.
- Manual timeout: 30 second whole-search timeout, owned by `SearchLyricsViewModel`; partial results remain visible.
- Source priority: keep the UI/settings, apply to both automatic and manual search as a near-equal tiebreaker only.
- Search window open behavior: auto-search current track immediately.
- Search button while active: unchanged fields → Cancel; changed fields → Search Again; field edits alone keep current partial results visible until Search Again starts.
- Apply shortcut: plain Return searches only; applying requires button click, double-click row, or `Command-Return`.
- Search status detail: provider summary/coarse status; user-facing hidden count means hidden unlikely results, while rejected count remains diagnostic/internal.
- Artist-only search: exact artist first, title A–Z, karaoke within same title.
- Duplicate-looking results: keep separate rows, sort best duplicate first, show mic/source clarity.
- Unlikely results: hidden behind `Show unlikely results` toggle; once shown, they are selectable and applicable as an intentional manual override.
- Rejected results: never displayed, selectable, or applicable.
- LyricsKit provider event API: group-level only for this pass; individual providers keep the existing candidate-oriented API.
- LyricsKit provider event stream: non-throwing; provider failures are event values, and `completed` means all provider/plugin work finished normally.
- LRCLIB exact lookup: use `LyricsSearchRequest.UserInfoKey.albumName`; keep `/api/search` for all searches, additionally run `/api/get` for complete title+artist+album+duration requests, and deduplicate exact/broad duplicate items with `/api/get` winning metadata/source-trace ties.
- Album metadata: set only for automatic current-track searches; manual search requests do not include album in this pass.
- Manual search without current track: search, preview, and drag/export stay available; Apply is disabled.
- Strict search setting: remove it; the evaluator/ranker replaces `Lyrics.isMatched()` as the only correctness gate.
- Implementation order: update LyricsKit and LyricsX local dependency integration before wiring evaluator/ranker into search.
- Evaluator/ranker purity: do not depend on LyricsKit provider events.
- Automated test expansion: final hardening phase after implementation is wired, with build/typecheck/manual checks during earlier phases.
- Provider-specific rich-timing work: deferred; LyricsX detects karaoke generically from inline timing, not from provider identity.
- Musixmatch richsync: not part of this plan.
