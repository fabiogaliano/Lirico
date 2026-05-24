# SR-04 — Pure evaluator/ranker core in LyricsXFoundation

## Goal

Introduce the shared pure search-domain model in `LyricsXFoundation`: search modes, karaoke detection, evaluation, ranking, and enough package tests to make downstream app integration safe.

## Depends on / blocks

- **Depends on:** `SR-03`
- **Blocks:** `SR-05`

## Scope

- Add `LyricsSearchMode`, `LyricsSyncKind`, `LyricsCandidateEvaluation`, `EvaluatedLyricsCandidate`, `LyricsCandidateRankingConfiguration`, `LyricsCandidateEvaluator`, and `LyricsCandidateRanker`.
- Add normalization/tokenization helpers needed by the evaluator.
- Add `Lyrics.syncKind` / `Lyrics.isKaraokeTimed` helpers based on inline timetag coverage.
- Implement mode-specific evaluation rules for title+artist, title-only, and artist-only search.
- Implement set-level ranker rules for karaoke preference, loose-fallback handling, near-equal source priority, and artist-only title ordering.
- Add package tests covering the core ranking/evaluation rules needed to unblock pipeline consumers.

## Out of scope

- LyricsKit provider events.
- LyricsX pipeline event mapping.
- Search window or session integration.
- Strict-search preference removal from the app target.

## Likely touchpoints

- `/Users/f/Core/dev/projects/LyricsX/LyricsXPackage/Sources/LyricsXFoundation/Search/`
- `/Users/f/Core/dev/projects/LyricsX/LyricsXPackage/Tests/LyricsXFoundationTests/Search/`
- Possibly exported entry points in `/Users/f/Core/dev/projects/LyricsX/LyricsXPackage/Sources/LyricsXFoundation/LyricsXFoundation.swift`

## Constraints and decisions to honor

Primary references:
- `../search-ranking-overhaul.md` — **Domain model changes**, **Evaluator contract**, **Normalization role**, **Sync detection**, **Ranking and collection rules**, **Edge cases**, **Resolved decisions**
- `../phases.md` — **Shared-contract gates**, **Phase 2**

Must honor:
- The evaluator decides correctness tier/visibility before numeric ordering.
- Duration and album are tiebreakers only.
- `Lyrics.quality` is not the primary ranking signal.
- Source priority belongs in the collection ranker only.
- Package code must not depend on app-side settings/defaults types.

## Acceptance criteria

- The new search-domain types exist in `LyricsXFoundation` with stable public shapes suitable for app integration.
- The evaluator rejects wrong-title candidates in title-based modes according to the plan rules.
- Artist-only evaluation and ranking follow the exact/loose catalog rules and title A–Z ordering.
- Karaoke detection requires meaningful inline-timing coverage rather than one stray `[tt]` line.
- Package tests cover representative correctness, karaoke-threshold, source-priority-window, and title/artist-mode cases.

## Risks or ambiguity

- Over-broad normalization could collapse unrelated titles/artists.
- Pairwise comparator thinking can leak into a set-level ranker; keep collection rules collection-aware.