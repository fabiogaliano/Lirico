# SR-06 — Manual search overhaul on top of evaluated candidates

## Goal

Rework manual search to consume evaluated candidates directly and deliver the approved result filtering, karaoke indicator, search modes, provider summary status, and Search/Cancel/Search Again behavior.

## Depends on / blocks

- **Depends on:** `SR-05`
- **Blocks:** `SR-08`

## Scope

- Update manual request construction to support title+artist, title-only, and artist-only search modes.
- Store evaluated candidates rather than raw `Lyrics` in the view model.
- Partition results into visible likely rows, loose fallback when appropriate, hidden unlikely rows, and never-visible rejected rows.
- Add/adjust the row model so karaoke rows show the approved mic indicator and source display stays canonical.
- Add the `Show unlikely results (N)` toggle and the selection/preview/artwork clearing rules when hidden rows disappear.
- Add `SearchStatus` and provider summary/coarse status updates.
- Implement button states and keyboard behavior: Search / Cancel / Search Again, Return, Escape, Command-Return, double-click apply.
- Keep manual search usable with no current track while leaving Apply disabled in that case.

## Out of scope

- Automatic search acceptance/finalization behavior.
- Final threshold tuning.
- Provider-specific rich-timing work.

## Likely touchpoints

- `/Users/f/Core/dev/projects/Lirico/Lirico/Search/SearchLyricsViewModel.swift`
- `/Users/f/Core/dev/projects/Lirico/Lirico/Search/SearchLyricsView.swift`
- `/Users/f/Core/dev/projects/Lirico/Lirico/Search/SearchLyricsWindowController.swift`
- `/Users/f/Core/dev/projects/Lirico/Lirico/Component/LyricsSearchPipeline.swift`
- `/Users/f/Core/dev/projects/Lirico/Lirico/Component/SearchSettings.swift`

## Constraints and decisions to honor

Primary references:
- `../search-ranking-overhaul.md` — **Manual search behavior**, **Search status model**, **Apply behavior**, **Search button, keyboard, and status behavior**, **UI surface changes**, **Edge cases**, **Resolved decisions**
- `../phases.md` — **Phase 3**

Must honor:
- Rejected results are never shown, selectable, draggable, previewable, or applicable.
- Unlikely results appear only behind the toggle; once shown they are intentional manual overrides.
- Title-based loose fallback shows only when no exact/strong normal rows exist.
- Artist-only search uses catalog ordering, not title-tier loose-fallback rules.
- Plain Return never applies lyrics.
- Opening the window still auto-searches the current track, but the active search must be visible in UI status.

## Acceptance criteria

- Manual search supports title+artist, title-only, and artist-only queries.
- The manual table shows canonical source names and a mic indicator for karaoke rows.
- `Show unlikely results (N)` appears only when there are unlikely rows and obeys the selection invalidation rules.
- Partial results remain visible across failure/cancel/timeout states with user-facing status text.
- Search/Cancel/Search Again and keyboard behavior match the plan.
- With no current track, search/preview/drag still work and Apply stays disabled.

## Risks or ambiguity

- `SearchLyricsViewModel.swift` and `SearchLyricsView.swift` are both high-conflict files.
- The state model must avoid illegal combinations like “Apply enabled for a hidden row” or “preview showing for a filtered-out row.”