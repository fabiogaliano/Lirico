import Foundation
import LyricsXFoundation

/// The canonical list of available lyrics source names, derived from the known provider registry.
/// Both `LyricsSelector` and `PreferenceSourceViewController` read from this source of truth.
let availableLyricsSources: [String] = LyricsProviders.Service.allCases.map(\.displayName)

/// `LyricsSelector` owns the "which lyrics wins?" concept end-to-end:
///
/// - **Source-order normalization**: filters stale source names from `defaults[.lyricsSourcePriorityOrder]`
///   and appends any new sources that have been added since the order was last saved.
///   Normalization runs at app launch (via `_ = LyricsSelector.shared` in `applicationDidFinishLaunching`)
///   and whenever the preferences pane saves a new order (via `normalize(against:)`).
///
/// - **Priority comparison**: `hasHigherPriority(_:over:)` replaces the free function
///   `lyricsHasHigherPriority(_:over:)` from `Global.swift`.
///
/// - **Collection-window state**: `LyricsCollector` encapsulates the per-search accumulation
///   state (accept-first, then keep collecting for a bounded window) so the loop in
///   `LyricsSession.currentTrackChanged` no longer holds raw `Bool`/`Date` locals.
final class LyricsSelector {
    static let shared = LyricsSelector()

    private init() {
        normalize(against: availableLyricsSources)
    }

    // MARK: - Normalization

    /// Normalize the persisted priority order against the current canonical source list:
    /// removes unknown source names and appends any new sources at the end.
    ///
    /// Call this at app launch and whenever the preferences pane writes a new order.
    func normalize(against knownSources: [String]) {
        let raw = defaults[.lyricsSourcePriorityOrder] ?? knownSources
        var normalized = raw.filter { knownSources.contains($0) }
        for source in knownSources where !normalized.contains(source) {
            normalized.append(source)
        }
        defaults[.lyricsSourcePriorityOrder] = normalized
    }

    // MARK: - Priority comparison

    /// Returns true if `candidate` should replace `current` as the displayed lyrics.
    ///
    /// - When `lyricsSourcePriorityEnabled` is off, falls back to quality comparison only.
    /// - When `current` is nil, any candidate is accepted unconditionally.
    /// - Otherwise, compares source-order indices (lower index = higher priority),
    ///   breaking ties with `Lyrics.quality`.
    func hasHigherPriority(_ candidate: Lyrics, over current: Lyrics?) -> Bool {
        guard let current = current else { return true }

        if defaults[.lyricsSourcePriorityEnabled] {
            let order = defaults[.lyricsSourcePriorityOrder] ?? []
            let normalizedOrder = order.map { $0.lowercased() }

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
    func insert(_ candidate: Lyrics, into results: inout [Lyrics]) {
        if let idx = results.firstIndex(where: { hasHigherPriority(candidate, over: $0) }) {
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
