import Combine
import Foundation
@preconcurrency import LyricsKit
import LiricoFoundation

// MARK: - LyricsSearchEvent

enum LyricsSearchEvent {
    case providerStarted(source: String)
    case candidate(EvaluatedLyricsCandidate)
    case providerFinished(source: String, yieldedCount: Int)
    case providerFailed(source: String, message: String, yieldedCount: Int)
    case completed
}

// MARK: - LyricsSearchPipeline

@MainActor
final class LyricsSearchPipeline {
    private var providerGroup: LyricsProviders.Group = LyricsProviders.Group()
    private let settings: SearchSettings
    private let candidateProcessor: LyricsSearchCandidateProcessor
    private var cancelBag = Set<AnyCancellable>()

    init(settings: SearchSettings = SearchSettings(), preparation: LyricsPreparation) {
        self.settings = settings
        candidateProcessor = LyricsSearchCandidateProcessor(preparation: preparation)
        settings.musixmatchTokenPublisher()
            .sink { [weak self] in
                Task { @MainActor in
                    self?.rebuildProviders()
                }
            }
            .store(in: &cancelBag)
        rebuildProviders()
    }

    func events(
        for request: LyricsSearchRequest,
        mode: LyricsSearchMode,
        requestedDuration: TimeInterval?,
        requestedAlbum: String?
    ) -> AsyncStream<LyricsSearchEvent> {
        let group = providerGroup
        let processor = candidateProcessor

        return AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                var arrivalIndex = 0
                for await rawEvent in group.events(for: request) {
                    guard !Task.isCancelled else { break }

                    switch rawEvent {
                    case .providerStarted(let source, _):
                        continuation.yield(.providerStarted(source: source))

                    case .candidate(let source, let lyrics):
                        let candidate = await processor.prepareCandidate(
                            source: source,
                            lyrics: lyrics,
                            mode: mode,
                            requestedDuration: requestedDuration,
                            requestedAlbum: requestedAlbum,
                            arrivalIndex: arrivalIndex
                        )
                        arrivalIndex += 1
                        continuation.yield(.candidate(candidate))

                    case .providerFinished(let source, _, let count):
                        continuation.yield(.providerFinished(source: source, yieldedCount: count))

                    case .providerFailed(let source, _, let message, let count):
                        continuation.yield(.providerFailed(source: source, message: message, yieldedCount: count))

                    case .completed:
                        continuation.yield(.completed)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func rebuildProviders() {
        let descriptors = makeProviderDescriptors(musixmatchToken: settings.musixmatchToken)
        providerGroup = LyricsProviders.Group(descriptors: descriptors)
    }
}

private actor LyricsSearchCandidateProcessor {
    private let preparation: LyricsPreparation
    private let evaluator = LyricsCandidateEvaluator()

    init(preparation: LyricsPreparation) {
        self.preparation = preparation
    }

    func prepareCandidate(
        source: String,
        lyrics: Lyrics,
        mode: LyricsSearchMode,
        requestedDuration: TimeInterval?,
        requestedAlbum: String?,
        arrivalIndex: Int
    ) -> EvaluatedLyricsCandidate {
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
        return EvaluatedLyricsCandidate(
            lyrics: lyrics,
            evaluation: evaluation,
            arrivalIndex: arrivalIndex
        )
    }
}

// Provider descriptor construction lives in `LiricoFoundation`
// (`makeProviderDescriptors`) so the app and out-of-app tooling share one
// canonical source list.
