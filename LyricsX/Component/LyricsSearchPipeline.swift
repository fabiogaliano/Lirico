import Combine
import Foundation
@preconcurrency import LyricsKit
import LyricsXFoundation

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
        let descriptors = makeDescriptors(musixmatchToken: settings.musixmatchToken)
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

// MARK: - Descriptor construction

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
