import Foundation
import LyricsXFoundation

/// Returns the canonical list of available lyrics source names for the given settings.
///
/// Derived from the same `makeDescriptors` path that `LyricsSearchPipeline`
/// uses to build the active provider group, so source-priority preferences
/// and emitted candidate source names always refer to the same strings.
/// Musixmatch is included only when a non-empty token is present in `settings`,
/// exactly matching the provider group `LyricsSearchPipeline.rebuildProviders()` builds.
func availableLyricsSources(for settings: SearchSettings) -> [String] {
    makeDescriptors(musixmatchToken: settings.musixmatchToken).map(\.source)
}

/// `LyricsSelector` owns source-order normalization for the preferences UI.
///
/// All per-candidate priority comparison and collection-window logic has been
/// migrated to `LyricsCandidateRanker` (SR-07). The only remaining
/// responsibilities are:
/// - **Source-order normalization** (`normalize(against:settings:)`):
///   filters stale source names from the persisted priority order and appends
///   any new sources that have been added since it was last saved. Run at app
///   launch and whenever the preferences pane saves a new order.
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
}
