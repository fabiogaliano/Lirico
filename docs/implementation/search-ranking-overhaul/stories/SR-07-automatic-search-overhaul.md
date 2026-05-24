# SR-07 — Automatic search overhaul with deadline and local-upgrade policy

## Goal

Replace the current automatic accept-first flow with evaluated candidate collection, an explicit 15-second finalization deadline, and the approved local-lyrics upgrade policy.

## Depends on / blocks

- **Depends on:** `SR-05`
- **Blocks:** `SR-08`

## Scope

- Update `LyricsSession` automatic search to consume the evaluated event stream.
- Track current best evaluated candidate, show interim strong matches, and re-rank as better candidates arrive.
- Finalize on provider completion or the 15-second deadline.
- Add explicit loose-fallback gating for automatic search.
- Implement the local-upgrade policy for embedded/beside-track/saved-path lyrics, including synthetic local source names for diagnostics/evaluation.
- Ensure manual `select(...)` / Apply cancels the in-flight automatic search and prevents later automatic finalization/export from replacing the user’s choice.
- Move automatic export/persist behavior to final-result-only semantics.

## Out of scope

- Search window UI changes.
- Final cleanup of obsolete compatibility code.
- Provider-specific timing improvements.

## Likely touchpoints

- `/Users/f/Core/dev/projects/LyricsX/LyricsX/Component/LyricsSession.swift`
- `/Users/f/Core/dev/projects/LyricsX/LyricsX/Component/LocalLyricsLoader.swift`
- `/Users/f/Core/dev/projects/LyricsX/LyricsX/Component/LyricsSearchPipeline.swift`
- `/Users/f/Core/dev/projects/LyricsX/LyricsX/Component/SearchSettings.swift`
- `/Users/f/Core/dev/projects/LyricsX/LyricsX/Search/SearchLyricsViewModel.swift`

## Constraints and decisions to honor

Primary references:
- `../search-ranking-overhaul.md` — **Automatic search behavior**, **Loose fallback**, **Local lyrics upgrade policy**, **Pipeline/workflow changes**, **Cancellation**, **Timeouts**, **Resolved decisions**
- `../phases.md` — **Phase 4**, **Critical serial path**

Must honor:
- Wrong-song candidates must never beat or replace the requested song.
- Interim automatic results are display-only for persistence/export purposes.
- Local karaoke is kept; local line-synced lyrics can be upgraded only by clearly better strong remote results under the approved policy.
- Source priority cannot force a local replacement.
- No late events update `currentLyrics` after track change, manual clear/apply, cancellation, or deadline.

## Acceptance criteria

- Automatic search consumes evaluated candidates rather than raw quality/source-priority comparison.
- The first strong acceptable candidate can display quickly, but slower stronger/karaoke candidates can still win before finalization.
- The 15-second deadline finalizes exactly once.
- Final-only export/persist behavior is enforced.
- Local karaoke is never replaced by remote results; local line-synced lyrics upgrade only under the approved exact/strong rules.
- Manual selection cancels the active automatic search and remains final.

## Risks or ambiguity

- The state machine around search freshness, finalization, and manual override is the highest-risk logic in the whole effort.
- Be careful not to destructively rewrite user-provided local files during remote upgrades.