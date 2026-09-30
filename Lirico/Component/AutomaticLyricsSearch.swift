import Foundation
import LiricoFoundation

// MARK: - AutomaticLyricsSearch

/// Runs one track's automatic search: feeds provider results into an
/// `AutomaticLyricsSelection` until every provider finishes or the deadline passes,
/// and reports its decisions. `LyricsSession` owns the state those decisions are
/// applied to (current lyrics, track association, persistence, export).
@MainActor
final class AutomaticLyricsSearch {
    typealias Decision = AutomaticLyricsSelection.Decision

    struct Request {
        let title: String
        let artist: String
        let album: String?
        let duration: TimeInterval?
        let policy: AutomaticAcceptancePolicy
    }

    private let pipeline: LyricsSearchPipeline
    private let searchSettings: SearchSettings

    init(pipeline: LyricsSearchPipeline, searchSettings: SearchSettings) {
        self.pipeline = pipeline
        self.searchSettings = searchSettings
    }

    /// Runs until every provider finishes or the deadline passes, whichever comes
    /// first, then reports `.finished` exactly once. Stops reporting as soon as
    /// `isCurrent` turns false (track changed, or the user picked or cleared lyrics).
    ///
    /// - Parameter displayed: the lyrics currently on screen.
    func run(
        _ request: Request,
        isCurrent: @escaping @MainActor @Sendable () -> Bool,
        displayed: @escaping @MainActor @Sendable () -> Lyrics?,
        report: @escaping @MainActor @Sendable (Decision) -> Void
    ) async {
        let query = LyricsSearchQuery.automatic(
            title: request.title,
            artist: request.artist,
            album: request.album,
            duration: request.duration
        )
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.collect(query, policy: request.policy, isCurrent: isCurrent, displayed: displayed, report: report)
            }
            group.addTask {
                try? await Task.sleep(for: AutomaticLyricsSelection.deadline)
            }
            // Whichever finishes first wins; the other is cancelled (DEC-003).
            await group.next()
            group.cancelAll()
        }
    }

    /// Feeds the query's candidates to a selection until the stream ends, which is also
    /// how the deadline stops it (by cancelling this task), then reports `.finished`.
    private func collect(
        _ query: LyricsSearchQuery,
        policy: AutomaticAcceptancePolicy,
        isCurrent: @MainActor () -> Bool,
        displayed: @MainActor () -> Lyrics?,
        report: @MainActor (Decision) -> Void
    ) async {
        var selection = AutomaticLyricsSelection(
            mode: query.mode,
            policy: policy,
            configuration: searchSettings.rankingConfiguration
        )
        for await event in pipeline.events(for: query) {
            guard isCurrent() else { break }
            guard case .candidate(let candidate) = event else { continue }
            selection.add(candidate, displayed: displayed()).forEach(report)
        }
        guard isCurrent() else { return }
        report(selection.finish(displayed: displayed()))
    }
}
