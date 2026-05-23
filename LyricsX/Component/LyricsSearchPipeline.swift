import Combine
import Foundation
import LyricsXFoundation

/// One-stop owner for lyrics search:
///
/// - rebuilds the `LyricsProvider` group from the no-auth services plus the
///   optional Musixmatch token whenever the token changes,
/// - streams candidates for a `LyricsSearchRequest`,
/// - prepares every candidate via the injected `LyricsPreparation` and marks
///   it dirty so the caller can persist without re-running that policy,
/// - optionally drops candidates that fail strict matching.
///
/// Both automatic search (`LyricsSession.currentTrackChanged`) and manual
/// search (`SearchLyricsViewController.searchAction`) go through this single
/// type. Callers stay responsible for things only they know — request
/// freshness, priority comparison, collection windows, and UI updates.
@MainActor
final class LyricsSearchPipeline {
    private var providerGroup: LyricsProvider = LyricsProviders.Group()
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

    /// Returns a stream of prepared, dirty-marked lyrics for `request`. When
    /// `strict` is true, candidates that don't pass `Lyrics.isMatched()` while
    /// strict search is currently enabled are dropped before reaching the
    /// caller.
    func candidates(for request: LyricsSearchRequest, strict: Bool) -> AsyncThrowingStream<Lyrics, Error> {
        // Snapshot the manager so a mid-stream token change can't swap providers
        // out from under an in-flight search.
        let manager = providerGroup
        let settings = settings
        let preparation = preparation
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await lyrics in manager.lyrics(for: request) {
                        if strict, settings.strictSearchEnabled, !lyrics.isMatched() { continue }
                        preparation.prepare(lyrics)
                        lyrics.metadata.needsPersist = true
                        continuation.yield(lyrics)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func rebuildProviders() {
        var providers: [LyricsProvider] = LyricsProviders.Service.noAuthenticationRequiredServices
            .map { $0.create() }
        if let token = settings.musixmatchToken, !token.isEmpty {
            providers.append(LyricsProviders.Musixmatch(usertoken: token))
        }
        providerGroup = LyricsProviders.Group(providers: providers)
    }
}
