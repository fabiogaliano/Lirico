# Handoff — Major Architectural Arc: Lyrics State as a Single Concept

Multi-session architectural transformation that collapses LyricsX's
fragmented lyrics-state ownership into one well-bounded type.

You are continuing architectural work on LyricsX at
`/Users/f/Core/dev/projects/LyricsX`. Read CLAUDE.md in the repo root, and
read `claudedocs/handoff-surgical-pass.md` if it exists — that handoff
should be done first since it tidies a few items that make this arc
cleaner.

## The vision

**Today** the lyrics state (which lyrics are loaded, which line is active,
who plays them, who searches for them) is fragmented across:

- `AppController.shared` — a god-object holding `currentLyrics`,
  `currentLineIndex`, search lifecycle, persistence routing, conversion
  routing. Five concerns, one type.
- `PlaybackClock.shared` — writes BACK to `AppController.shared.currentLineIndex`
  directly (see `PlaybackClock.swift:62-63`). Two singletons in a cycle.
- `let selectedPlayer = MusicPlayers.Selected.shared` — module-level global
  in `LyricsX/Utility/Global.swift:29`. Implicitly visible to every Swift
  file in the project.
- Three external writers of `AppController.shared.currentLyrics`:
  `SearchLyricsViewController` (user picks a search result),
  `AppDelegate` (menu actions like "wrong lyrics" or "do not search for
  this album"), and various internal AppController paths.

**After this arc** the architecture passes three deterministic tests:

1. **Single-writer test**:
   `grep -rn "\.currentLyrics =" --include="*.swift" /Users/f/Core/dev/projects/LyricsX/LyricsX/`
   returns hits only inside `LyricsSession.swift` (renamed from
   `AppController.swift`).

2. **No-global test**:
   `grep -rn "let selectedPlayer" --include="*.swift" /Users/f/Core/dev/projects/LyricsX/LyricsX/`
   returns zero hits. Every consumer holds an injected `PlayerHandle`
   reference instead.

3. **No-cycle test**: `PlaybackClock.swift` does not contain the string
   `AppController` or `LyricsSession`. The clock is a pure publisher;
   the session subscribes.

The shape that emerges:

```swift
final class LyricsSession {
    // Read surface
    @Published private(set) var state: LyricsState     // (lyrics: Lyrics?, lineIndex: Int?)

    // Command surface
    func select(_ lyrics: Lyrics)
    func importRaw(_ text: String) throws
    func clear()

    // Wiring (constructor-injected)
    init(player: PlayerHandle, persister: LyricsPersister, clock: PlaybackClock)
}
```

## Why this is one arc, not three independent refactors

The three sub-changes (#2, #5, #1 in the original proposal numbering) are
ordered prerequisites:

- **#1 (LyricsSession)** wants a single owner for state mutation. If
  PlaybackClock still writes to it directly, the single-writer test
  fails. So **#2 must come first**.
- **#1 also** wants the session's constructor to receive its
  dependencies. The biggest one is the player. If `selectedPlayer` is
  still a module-level global, the constructor injection is incomplete.
  So **#5 must come before #1**.
- **#2 and #5 alone** are sideways moves — they don't pay off until #1
  consolidates the writers. But trying to do all three in one session
  would produce an unreviewable mega-commit. Hence the staging.

**Lock-in: do not skip steps or reorder.**

## Renames are encouraged and authorized

The project owner has explicitly waived "preserve names for stability."
Concrete rename calls baked into this arc:

- `AppController` → `LyricsSession` (the core rename — current name is
  misleading; AppKit's "Controller" suffix implies an NSController
  subclass, which this isn't).
- `AppController.shared` → constructed-and-owned-by-AppDelegate
  (singleton goes away, but the instance is still effectively unique
  during the app's lifetime).
- `selectedPlayer` → injected as `player: PlayerHandle` on every
  consumer's constructor or `set(player:)` method.

Smaller rename opportunities that the implementation agents may discover
mid-arc are also OK if they improve clarity. Don't preserve names for
their own sake.

## Orchestration pattern (proven to work)

For each session, for each piece of work:

1. **Implementation agent** (general-purpose): brief it with specific
   files + line numbers, behavior constraints (pure refactor or fix
   surfaced as side effect), where new files go, the `project.pbxproj`
   add pattern, the build command, and an explicit "do not commit"
   instruction.

2. **Read the agent's diff yourself**, then spawn an **independent
   review agent** with explicit scenario checks tailored to this
   session.

3. **You commit** (not the agent). Before each commit:
   ```
   git -C /Users/f/Core/dev/projects/LyricsX checkout -- "LyricsX/Supporting Files/Info.plist"
   ```

4. Commit subject: `refactor: <verb> <noun>`. Body explains why in 2-3
   sentences, mentions any latent fix surfaced as a side effect.

## Verification (every session ends with this green)

```
xcodebuild -project /Users/f/Core/dev/projects/LyricsX/LyricsX.xcodeproj \
  -scheme LyricsX -configuration Debug build 2>&1 | \
  grep -E "(BUILD|error:|warning:)" | tail -10
```

Must end with `** BUILD SUCCEEDED **`. **Never leave the codebase
half-migrated between sessions.** Every session ends in a fully-working
green-build state with all behavior preserved.

## Traps to watch for

- **Stale-snapshot trap**: when you replace a live property read with a
  stored `@Published var` that's only written periodically, you've
  introduced staleness. Prefer computed properties for values callers
  expect to be live. (PlayerHandle's `playbackTime` MUST stay a live
  computed property when wrapped.)
- **Storyboard-instantiated VCs**: VCs created from a storyboard don't
  have an explicit Swift `init` you can extend. Inject via a `func
  setPlayerHandle(_:)` method called after instantiation, OR have the
  VC look up its dependencies from a registry owned by AppDelegate.
- **`AppController.shared` references at storyboard time**: anything
  that runs during nib loading and references the singleton needs
  special care during the rename — the singleton may not be the same
  instance during the transition.
- **Combine subscription lifetime**: subscriptions stored in
  `cancelBag` survive as long as the owner does. When AppController
  becomes LyricsSession and is no longer a singleton, ensure its
  cancelBag still scopes correctly.

---

# Sessions

## Session A — PlaybackClock as publisher (proposal #2)

### Vision

Today `PlaybackClock.shared.tick()` updates
`AppController.shared.currentLineIndex` directly (file
`LyricsX/Component/PlaybackClock.swift`, lines 62-63):

```swift
if AppController.shared.currentLineIndex != index {
    AppController.shared.currentLineIndex = index
}
```

After: PlaybackClock exposes a publisher. AppController subscribes.

```swift
// PlaybackClock.swift (after)
final class PlaybackClock {
    static let shared = PlaybackClock()

    /// Emits the current active line index whenever it changes.
    /// nil means no current line (no lyrics, paused, before-first-line, etc.).
    var currentLineIndex: AnyPublisher<Int?, Never> { /* exposes internal CurrentValueSubject */ }

    func tick() { /* same self-rescheduling behavior, but updates the subject not AppController */ }
}
```

```swift
// AppController.swift (after)
init() {
    // ...existing setup...
    PlaybackClock.shared.currentLineIndex
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.currentLineIndex = $0 }
        .store(in: &cancelBag)
}
```

### Files affected
- `LyricsX/Component/PlaybackClock.swift` — exposes a new
  `CurrentValueSubject<Int?, Never>` internally, vended as
  `AnyPublisher`. Remove the direct AppController write.
- `LyricsX/Component/AppController.swift` — add the subscription in
  `init`. The existing `@Published var currentLineIndex` stays — it's
  still the canonical state holder, just sourced from the publisher
  now.

### Implementation brief skeleton

The implementation agent should be told:

> Read `PlaybackClock.swift` fully. Identify the self-rescheduling timer
> behavior (look for the re-fire chain that owns the next-line scheduling).
> Identify every site that writes `currentLineIndex` (currently only
> PlaybackClock writes to AppController's @Published property; verify
> with grep).
>
> Restructure PlaybackClock so it owns a private
> `CurrentValueSubject<Int?, Never>` named `currentLineIndexSubject`,
> exposed publicly as `var currentLineIndex: AnyPublisher<Int?, Never> {
> currentLineIndexSubject.eraseToAnyPublisher() }`.
>
> The `tick()` method now updates the subject, not AppController. The
> self-rescheduling timer behavior is preserved exactly. Note:
> PlaybackClock STILL reads from AppController (`AppController.shared.currentLyrics`
> and `.adjustedTimeDelay`) — that direction is fine for now; we're only
> reversing the write direction. Session C will eliminate the read
> dependency.
>
> In AppController, add a subscription in `init()` that mirrors the
> publisher's value into `self.currentLineIndex`. The @Published var
> stays; what changes is who writes it.
>
> This is a PURE refactor. Behavior must be byte-identical: same line
> indices emitted at the same logical moments. Build and verify before
> reporting. Do not commit.

### Reviewer brief skeleton

> Trace the self-rescheduling timer: it must still fire at the same
> moments and compute the same next-fire time. Trace the
> currentLineIndex observation chain: a tick that produces a new index
> must propagate to AppController.shared.currentLineIndex synchronously
> on the main queue (or whatever queue the original write was on —
> verify against pre-refactor behavior). Confirm the karaoke overlay
> and HUD line-active states still update at the right moments.
> Confirm no race condition between the timer fire and the subscription
> dispatch. Build green.

### Commits expected: 2-3

Likely shape:
1. `refactor: expose PlaybackClock.currentLineIndex as a publisher` — adds the publisher; AppController subscribes; PlaybackClock still does the direct write (transitional).
2. `refactor: remove PlaybackClock direct AppController write` — flip; now only the subscription writes.

OR a single combined commit if the implementer can land it cleanly in
one diff. Either is fine.

### Session A end state
- PlaybackClock no longer mutates AppController.
- AppController still owns `@Published var currentLineIndex` (the state
  holder).
- Tests 1 and 3 from the Vision: not yet passing (currentLyrics still
  has multiple writers; PlaybackClock still READS AppController). Session
  A only reverses the write direction.

---

## Session B — Inject PlayerHandle (proposal #5)

### Vision

Today `let selectedPlayer = MusicPlayers.Selected.shared` lives in
`LyricsX/Utility/Global.swift:29`. Every Swift file in the project can
reference `selectedPlayer` without declaring a dependency. Hidden
dependencies are AI-navigability landmines.

After: define `protocol PlayerHandle` exposing the methods the app
actually uses. The Music Player package's `MusicPlayers.Selected` is
wrapped by an adapter. AppDelegate constructs the adapter and injects
it into every consumer. The global is deleted.

### Step 1 — Catalog the surface

Grep first:
```
grep -rn "selectedPlayer" --include="*.swift" /Users/f/Core/dev/projects/LyricsX/LyricsX/
```

Expect ~10-15 hits. For each hit, note which method/property is accessed.
This becomes the PlayerHandle protocol's minimal surface — only methods
ACTUALLY USED appear in the protocol.

### Step 2 — Define the protocol

`LyricsX/Component/PlayerHandle.swift`:

```swift
import Combine
import MusicPlayer

/// The subset of MusicPlayer functionality this app actually uses.
/// Keep this protocol minimal — only methods that have at least one
/// real call site belong here.
protocol PlayerHandle: AnyObject {
    var name: MusicPlayerName { get }
    var currentTrack: MusicTrack? { get }
    var playbackState: PlaybackState { get }
    var playbackTime: TimeInterval { get set }
    var currentTrackWillChange: AnyPublisher<Void, Never> { get }
    // ... add only what's actually called by the codebase
}

final class MusicPlayerSelectedHandle: PlayerHandle {
    private let player: MusicPlayers.Selected
    init(_ player: MusicPlayers.Selected) { self.player = player }
    // pass-through implementations
}
```

### Step 3 — Inject

For each consumer:
- If the consumer is a singleton (e.g., `AppController.shared`,
  `MenuBarLyricsController.shared`): convert to constructor injection if
  feasible, or accept a `setPlayerHandle(_:)` setter called by
  AppDelegate at startup.
- If the consumer is a storyboard-instantiated VC: AppDelegate sets the
  player handle on the VC after instantiation via a `setPlayerHandle(_:)`
  method.
- If the consumer is a free function: pass the handle as an explicit
  parameter.

AppDelegate becomes the dep-graph constructor:

```swift
// AppDelegate.swift (after)
private let playerHandle: PlayerHandle = MusicPlayerSelectedHandle(MusicPlayers.Selected.shared)

func applicationDidFinishLaunching(_ notification: Notification) {
    AppController.shared.setPlayerHandle(playerHandle)
    MenuBarLyricsController.shared.setPlayerHandle(playerHandle)
    // ... etc for every other handle consumer
    // (eager-init pattern still applies for the side-effect singletons)
}
```

### Step 4 — Delete the global

Once every site routes through an injected handle:
- Delete `let selectedPlayer = MusicPlayers.Selected.shared` from `Global.swift:29`.
- Verify the build still passes.

### Reviewer brief skeleton

> For each migration site, trace: was the original behavior preserved?
> Did any consumer access a property the protocol doesn't expose? If
> yes, the protocol is incomplete OR the consumer should not depend on
> that property (architectural question).
>
> Verify the `selectedPlayer` deletion-test grep returns zero hits.
> Verify storyboard-instantiated VCs receive their handle BEFORE they
> try to use it (check the init / setup ordering in AppDelegate). Build
> green.

### Commits expected: 5-8

Likely shape:
1. `refactor: introduce PlayerHandle protocol and adapter`
2. `refactor: inject PlayerHandle into AppController`
3. `refactor: inject PlayerHandle into MenuBarLyricsController`
4. `refactor: inject PlayerHandle into KaraokeLyricsController`
5. `refactor: inject PlayerHandle into TouchBar VCs`
6. `refactor: inject PlayerHandle into Search and Preferences VCs`
7. `refactor: delete selectedPlayer global`

Each commit isolates one consumer's migration. Smaller commits = safer
review.

### Session B end state
- `selectedPlayer` global is gone.
- Every consumer holds an explicit PlayerHandle reference.
- Test 2 from the Vision: PASSES.

---

## Session C — Introduce LyricsSession, rename AppController (proposal #1)

### Vision

The capstone. Today `AppController` owns five concerns. After this
session:

- **LyricsSession** (renamed from AppController) owns lyrics state
  mutation and exposes a command surface.
- **LyricsPersister** (new) owns writing to iTunes and to the saving
  path. Mirrors `LocalLyricsLoader` (the existing read-side). Maybe
  named `LyricsWriter` if it ends up only writing.
- **LyricsSearchCoordinator** (new) owns the network search lifecycle.
  May stay inside LyricsSession if it doesn't grow beyond a handful of
  methods — make the call at implementation time.
- **PlaybackClock** (unchanged from Session A) is already a publisher.
- **LineRenderer** (existing) handles Chinese conversion routing.

### Files affected

Major rewrite. AppController.swift becomes LyricsSession.swift. The
three external writer sites
(`SearchLyricsViewController.useLyricsAction`,
`AppDelegate.wrongLyrics`, `AppDelegate.doNotSearchLyricsForThisAlbum`)
migrate to call LyricsSession commands instead of writing
`currentLyrics` directly.

### Important: this brief is intentionally incomplete

Don't pre-write the detailed implementation brief for Session C now.
By the time you start Session C, Sessions A and B will have changed the
baseline — line numbers, method signatures, the writer-site inventory.

What this handoff DOES commit to:
- The final shape (LyricsSession with command surface).
- The three architecture tests must pass at session end.
- Rename `AppController` → `LyricsSession` is part of the change.
- Persistence extraction is part of the change.

What this handoff DEFERS to Session C's start:
- Exact line numbers to migrate (will have shifted).
- Whether persistence is one type or two.
- Whether search coordination is a separate type.
- The exact protocol shape of LyricsSession's command surface.

When starting Session C: re-grep the codebase, build a current-state
map, then write the implementation brief based on the actual
post-A-and-B baseline.

### Commits expected: 8-12

### Session C end state
- All three architecture tests pass.
- `AppController` is gone; `LyricsSession` is the new name.
- The lyrics state has a single writer.

---

## Session D — Cleanup, polish, post-mortem

### Goals

1. **Deletion-test sweep**: run the three architecture tests and any
   other concentration checks you care about.

2. **Update CLAUDE.md**: the project's own documentation should
   reflect the new architecture. The "Data Flow" section in CLAUDE.md
   currently names `AppController.shared` — update it to LyricsSession.

3. **Postmortem**: one paragraph in `claudedocs/arc-postmortem.md`:
   - What the arc cost (sessions, commits, calendar time)
   - What it delivered (concretely, against the three tests)
   - What surprised you (latent bugs found, scope creep, anything that
     diverged from the plan)
   - What didn't get done (if anything was deferred or descoped)

4. **Defer or close** any candidate items from the original 11-item
   proposal that remain (e.g., proposal #3 ArtworkFetcher if not done in
   the surgical pass; #4 Controller folder rename; #6 AppDelegate
   split; #8 LyricsStore — likely don't bother; #10 KaraokeGradientFill).

### Commits expected: 1-3

---

## End-of-arc checklist

- [ ] Session A landed, Session B landed, Session C landed, Session D landed
- [ ] Architecture test 1: only LyricsSession.swift writes `currentLyrics`
- [ ] Architecture test 2: no `selectedPlayer` global
- [ ] Architecture test 3: PlaybackClock doesn't reference LyricsSession
- [ ] CLAUDE.md updated to reflect new architecture
- [ ] Postmortem written

## Project guardrails

- Swift 5 in the Xcode project setting, Swift 6.2 in `LyricsXPackage/Package.swift`.
  Prefer Combine over modern Concurrency in the main app.
- LyricsKit and MusicPlayer come from external SPM packages — don't modify them.
- No tests exist; do not invent a test suite mid-arc unless explicitly asked.
- `project.pbxproj` is UTF-8 text despite git showing diffs as "Bin".
- Don't skip pre-commit hooks (`--no-verify`).
- Storyboard surgery is risky — when a class rename touches IB, update
  every `customClass=` and `objectClassName=` reference in lockstep, or
  preserve the Obj-C runtime name with `@objc(OldName) class NewSwiftName`.
- Each session must end with `** BUILD SUCCEEDED **` and behavior preserved.
