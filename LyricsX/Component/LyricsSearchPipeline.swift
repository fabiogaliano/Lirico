import Combine
import Foundation
@preconcurrency import LyricsKit
import LyricsXFoundation

// MARK: - LyricsSearchEvent

/// App-level lifecycle events produced by `LyricsSearchPipeline.events(for:)`.
///
/// Maps raw `LyricsProviders.ProviderEvent` payloads into types the app cares
/// about: the `request` field on raw events is dropped (the caller holds it),
/// and raw `candidate` events are enriched with an `EvaluatedLyricsCandidate`.
enum LyricsSearchEvent {
    case providerStarted(source: String)
    case candidate(EvaluatedLyricsCandidate)
    case providerFinished(source: String, yieldedCount: Int)
    case providerFailed(source: String, message: String, yieldedCount: Int)
    case completed
}

// MARK: - LyricsSearchPipeline

/// One-stop owner for lyrics search:
///
/// - rebuilds the `LyricsProvider` group from the no-auth services plus the
///   optional Musixmatch token whenever the token changes,
/// - streams candidates for a `LyricsSearchRequest`,
/// - prepares every candidate via the injected `LyricsPreparation`, marks it
///   dirty, and keeps automatic-persistence gated until the caller explicitly
///   accepts the result.
///
/// Both automatic search (`LyricsSession.currentTrackChanged`) and manual
/// search (`SearchLyricsViewModel.search`) go through this single type.
/// Callers stay responsible for things only they know — request freshness,
/// priority comparison, collection windows, UI updates, and when persistence
/// becomes allowed.
@MainActor
final class LyricsSearchPipeline {
    private var providerGroup: LyricsProviders.Group = LyricsProviders.Group()
    private let settings: SearchSettings
    private let preparation: LyricsPreparation
    private var cancelBag = Set<AnyCancellable>()

    init(settings: SearchSettings = SearchSettings(), preparation: LyricsPreparation) {
        self.settings = settings
        self.preparation = preparation
        settings.musixmatchTokenPublisher()
            .sink { [weak self] in
                Task { @MainActor in
                    self?.rebuildProviders()
                }
            }
            .store(in: &cancelBag)
        rebuildProviders()
    }

    /// Returns a non-throwing app-level event stream for `request`.
    ///
    /// Every raw `ProviderEvent.candidate` is:
    ///   1. Canonicalized: `lyrics.metadata.service` is set to the event's
    ///      `source` before any further processing (source stamped first so
    ///      evaluation and the ranker always see the canonical name).
    ///   2. Prepared: `LyricsPreparation.prepare(_:)` is applied.
    ///   3. Evaluated: `LyricsCandidateEvaluator` assigns correctness/tier.
    ///   4. Wrapped: emitted as `.candidate(EvaluatedLyricsCandidate(...))`.
    ///      `.unlikely` and `.rejected` evaluations are included — consumers
    ///      decide what to show or select.
    ///
    /// `arrivalIndex` is a zero-based counter incremented for each candidate
    /// emitted to THIS app stream (not the raw provider stream), giving the
    /// ranker a stable final tiebreaker per search session.
    ///
    /// `.completed` is forwarded only when the raw stream emits it (i.e. all
    /// providers finished normally). If the consumer cancels the task or breaks
    /// out of the `for await`, the raw stream suppresses `.completed` per SR-01
    /// (DEC-003), so we never synthesize one — no `.completed` after cancellation.
    func events(
        for request: LyricsSearchRequest,
        mode: LyricsSearchMode,
        requestedDuration: TimeInterval?,
        requestedAlbum: String?
    ) -> AsyncStream<LyricsSearchEvent> {
        let group = providerGroup
        let preparation = preparation
        let evaluator = LyricsCandidateEvaluator()

        return AsyncStream { continuation in
            let task = Task {
                var arrivalIndex = 0
                for await rawEvent in group.events(for: request) {
                    switch rawEvent {
                    case .providerStarted(let source, _):
                        continuation.yield(.providerStarted(source: source))

                    case .candidate(let source, let lyrics):
                        // Canonicalize before preparation or evaluation so that
                        // source-priority ranking always compares against the same strings.
                        lyrics.metadata.service = source
                        preparation.prepare(lyrics)
                        lyrics.metadata.needsPersist = true
                        lyrics.metadata.persistenceAllowed = false
                        let evaluation = evaluator.evaluate(
                            lyrics: lyrics,
                            mode: mode,
                            requestedDuration: requestedDuration,
                            requestedAlbum: requestedAlbum
                        )
                        let candidate = EvaluatedLyricsCandidate(
                            lyrics: lyrics,
                            evaluation: evaluation,
                            arrivalIndex: arrivalIndex
                        )
                        arrivalIndex += 1
                        continuation.yield(.candidate(candidate))

                    case .providerFinished(let source, _, let count):
                        continuation.yield(.providerFinished(source: source, yieldedCount: count))

                    case .providerFailed(let source, _, let message, let count):
                        continuation.yield(.providerFailed(source: source, message: message, yieldedCount: count))

                    case .completed:
                        // Forward only when the raw stream emitted it; never synthesize.
                        continuation.yield(.completed)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func rebuildProviders() {
        let descriptors = makeDescriptors(musixmatchToken: settings.musixmatchToken)
        providerGroup = LyricsProviders.Group(descriptors: descriptors)
    }
}

// MARK: - Descriptor construction

/// The single source of truth for which providers are active and what their
/// canonical source names are. Both `LyricsSearchPipeline.rebuildProviders()`
/// and `availableLyricsSources(for:)` derive from this path so the source-priority
/// preference list and the emitted candidate source strings can never drift.
///
/// Musixmatch is included only when a non-empty token is provided, per DEC-001.
internal func makeDescriptors(musixmatchToken: String?) -> [LyricsProviders.ProviderDescriptor] {
    var descriptors: [LyricsProviders.ProviderDescriptor] = [
        LyricsProviders.ProviderDescriptor(
            source: LyricsProviders.ServiceID.netease.displayName,
            provider: LyricsProviders.Service.netease.create()
        ),
        LyricsProviders.ProviderDescriptor(
            source: LyricsProviders.ServiceID.qq.displayName,
            provider: LyricsProviders.Service.qq.create()
        ),
        LyricsProviders.ProviderDescriptor(
            source: LyricsProviders.ServiceID.kugou.displayName,
            provider: LyricsProviders.Service.kugou.create()
        ),
        LyricsProviders.ProviderDescriptor(
            source: LyricsProviders.ServiceID.lrclib.displayName,
            provider: LyricsProviders.Service.lrclib.create()
        ),
    ]
    if let token = musixmatchToken, !token.isEmpty {
        descriptors.append(LyricsProviders.ProviderDescriptor(
            source: LyricsProviders.ServiceID.musixmatch.displayName,
            provider: LyricsProviders.Service.musixmatch.create(
                LyricsProviders.MusixmatchOptions(usertoken: token)
            )
        ))
    }
    return descriptors
}
