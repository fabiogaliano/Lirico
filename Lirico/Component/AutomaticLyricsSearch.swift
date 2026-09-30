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
        isCurrent: @escaping @MainActor () -> Bool,
        displayed: @escaping @MainActor () -> Lyrics?,
        report: @escaping @MainActor (Decision) -> Void
    ) async {
        let query = LyricsSearchQuery.automatic(
            title: request.title,
            artist: request.artist,
            album: request.album,
            duration: request.duration
        )
        let stream = pipeline.events(for: query)
        // Both racing children run on the main actor, so sharing this is safe.
        var selection = AutomaticLyricsSelection(
            mode: query.mode,
            policy: request.policy,
            configuration: searchSettings.rankingConfiguration
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await event in stream {
                    guard isCurrent() else { break }
                    guard case .candidate(let candidate) = event else { continue }
                    selection.add(candidate, displayed: displayed()).forEach(report)
                }
            }
            group.addTask {
                try? await Task.sleep(for: AutomaticLyricsSelection.deadline)
            }
            // Whichever finishes first wins; the other is cancelled (DEC-003).
            await group.next()
            group.cancelAll()
        }

        guard isCurrent() else { return }
        report(selection.finish(displayed: displayed()))
    }
}
