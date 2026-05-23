import Foundation
import LyricsXFoundation

/// The canonical list of available lyrics source names, derived from the known provider registry.
let availableLyricsSources: [String] = LyricsProviders.Service.allCases.map(\.displayName)

/// `LyricsSelector` owns the "which lyrics wins?" concept end-to-end.
///
/// It's still a `shared` singleton because there is only ever one lyrics
/// selection happening at a time and the type itself is stateless: every
/// method takes a `SearchSettings` so the search-policy dependency is
/// explicit at the call site instead of hidden behind module-level `defaults`.
///
/// - **Source-order normalization** (`normalize(against:settings:)`):
///   filters stale source names from the persisted priority order and appends
///   any new sources that have been added since it was last saved. Run at app
///   launch and whenever the preferences pane saves a new order.
/// - **Priority comparison** (`hasHigherPriority(_:over:settings:)`):
///   decides whether a candidate should replace the current selection,
///   honoring source-order when enabled and falling back to `Lyrics.quality`.
/// - **Collection-window state** (`LyricsCollector`): per-search accept-first /
///   then-collect-for-a-window logic, kept here so the loop in
///   `LyricsSession.currentTrackChanged` no longer holds raw `Bool`/`Date`
///   locals.
final class LyricsSelector {
    static let shared = LyricsSelector()

    private init() {}

    // MARK: - Normalization

    /// Normalize the persisted priority order against the current canonical source list:
    /// removes unknown source names and appends any new sources at the end.
    func normalize(against knownSources: [String], settings: SearchSettings) {
        let raw = settings.sourcePriorityOrder.isEmpty ? knownSources : settings.sourcePriorityOrder
        var normalized = raw.filter { knownSources.contains($0) }
        for source in knownSources where !normalized.contains(source) {
            normalized.append(source)
        }
        settings.sourcePriorityOrder = normalized
    }

    // MARK: - Priority comparison

    /// Returns true if `candidate` should replace `current` as the displayed lyrics.
    ///
    /// - When `settings.sourcePriorityEnabled` is off, falls back to quality comparison only.
    /// - When `current` is nil, any candidate is accepted unconditionally.
    /// - Otherwise, compares source-order indices (lower index = higher priority),
    ///   breaking ties with `Lyrics.quality`.
    func hasHigherPriority(_ candidate: Lyrics, over current: Lyrics?, settings: SearchSettings) -> Bool {
        guard let current = current else { return true }

        if settings.sourcePriorityEnabled {
            let normalizedOrder = settings.sourcePriorityOrder.map { $0.lowercased() }

            let currentSource = (current.metadata.service ?? "").lowercased()
            let candidateSource = (candidate.metadata.service ?? "").lowercased()

            let currentIndex = normalizedOrder.firstIndex(of: currentSource) ?? Int.max
            let candidateIndex = normalizedOrder.firstIndex(of: candidateSource) ?? Int.max

            if currentIndex != candidateIndex {
                return candidateIndex < currentIndex
            }
        }

        return candidate.quality > current.quality
    }

    // MARK: - Collection window

    /// Returns a fresh collector for one search session.
    func makeCollector(window: TimeInterval) -> LyricsCollector {
        LyricsCollector(window: window)
    }

    // MARK: - Ordered insertion

    /// Insert `candidate` into `results` so the list stays sorted by
    /// `hasHigherPriority`. The manual search window uses this to mirror the
    /// priority order automatic search applies when accepting candidates.
    func insert(_ candidate: Lyrics, into results: inout [Lyrics], settings: SearchSettings) {
        if let idx = results.firstIndex(where: { hasHigherPriority(candidate, over: $0, settings: settings) }) {
            results.insert(candidate, at: idx)
        } else {
            results.append(candidate)
        }
    }
}

// MARK: - LyricsCollector

/// Encapsulates the "accept first immediately, then keep collecting for a bounded window" logic
/// that governs which incoming lyrics the streaming loop in `LyricsSession` should act on.
///
/// Create one collector per search via `LyricsSelector.shared.makeCollector(window:)`.
/// For each arriving `Lyrics`, call `nextDecision()`. When the `.accept` decision causes
/// `lyricsReceived` to actually update `currentLyrics`, call `notifyAccepted()` to start the
/// collection window. Until that call the collector keeps routing every arrival as a candidate
/// first pick (matching the original behaviour where the window only starts once a lyrics is
/// actually displayed).
struct LyricsCollector {
    let window: TimeInterval

    private var collectionStart: Date?

    init(window: TimeInterval) {
        self.window = window
    }

    enum Decision {
        case accept
        case stop
    }

    func nextDecision() -> Decision {
        guard let start = collectionStart else { return .accept }
        return Date().timeIntervalSince(start) > window ? .stop : .accept
    }

    /// Call this after an `.accept` decision causes `lyricsReceived` to update
    /// `LyricsSession.currentLyrics`. Starts the collection window on first call;
    /// subsequent calls are no-ops so the window measures from the first acceptance.
    mutating func notifyAccepted() {
        if collectionStart == nil {
            collectionStart = Date()
        }
    }
}
