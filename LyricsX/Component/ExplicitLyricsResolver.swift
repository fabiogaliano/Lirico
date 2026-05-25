import Combine
import Foundation
import GenericID
import LyricsXFoundation

// MARK: - ExplicitRestorationContext

/// The evidence available to restore one rendered lyrics document at display time.
///
/// `supportingCandidates` are the other fetched candidates for the same song,
/// kept around by the search/session layer so masked spans can be repaired by
/// cross-candidate consensus without changing which lyrics are selected.
struct ExplicitRestorationContext {
    let supportingCandidates: [Lyrics]
}

/// A per-render-pass closure that restores a single main lyric line.
///
/// `isTimedLine` is true for karaoke (word-timed) lines, where the displayed
/// glyph count must not change; the resolver maps that onto length-preserving
/// restoration in the pure engine.
typealias ExplicitLineRestoration = (_ text: String, _ isTimedLine: Bool) -> String

/// The display-time restoration closures for one render pass.
///
/// Main lines may use cross-candidate consensus. Translation lines must stay
/// lexicon-only because the supporting candidates are alternate main-lyrics
/// documents, not aligned translation evidence.
struct ExplicitRenderRestoration {
    let mainLine: ExplicitLineRestoration
    let translation: (_ text: String) -> String

    static let identity = ExplicitRenderRestoration(
        mainLine: { text, _ in text },
        translation: { $0 }
    )
}

// MARK: - ExplicitLyricsResolving

protocol ExplicitLyricsResolving: AnyObject {
    var isEnabled: Bool { get }
    /// Emits when the enablement flag or lexicon entries change, so display
    /// surfaces can recompute visible text without reloading lyrics.
    var settingsDidChange: AnyPublisher<Void, Never> { get }
    /// Builds the display-time restorers bound to `context`. Returns identity
    /// closures when the feature is disabled, so call sites stay branch-free.
    func makeRenderRestoration(context: ExplicitRestorationContext) -> ExplicitRenderRestoration
}

// MARK: - ExplicitLyricsResolver

/// App-side adapter between the explicit-restoration preferences and the pure
/// `ExplicitWordRestorer`. Owns the cached restorer and rebuilds it when the
/// lexicon entries change.
final class ExplicitLyricsResolver: ExplicitLyricsResolving {
    private let defaults: UserDefaults
    private var cachedRestorer: ExplicitWordRestorer
    private var cachedLexicon: [String]
    private let changeSubject = PassthroughSubject<Void, Never>()
    private var cancelBag = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let entries = defaults[.lyricsExplicitLexiconEntries] ?? []
        cachedLexicon = entries
        cachedRestorer = ExplicitWordRestorer(words: entries)

        defaults.publisher(for: [.lyricsExplicitRestorationEnabled, .lyricsExplicitLexiconEntries])
            .sink { [weak self] in self?.reload() }
            .store(in: &cancelBag)
    }

    var isEnabled: Bool {
        defaults[.lyricsExplicitRestorationEnabled]
    }

    var settingsDidChange: AnyPublisher<Void, Never> {
        changeSubject.eraseToAnyPublisher()
    }

    func makeRenderRestoration(context: ExplicitRestorationContext) -> ExplicitRenderRestoration {
        guard isEnabled else { return .identity }

        let restorer = cachedRestorer
        let supportingLineSets: [[String]] = context.supportingCandidates.map { lyrics in
            lyrics.lines
                .filter { $0.enabled && !$0.content.isEmpty }
                .map(\.content)
        }
        guard restorer.canRestore(hasAlternates: !supportingLineSets.isEmpty) else {
            return .identity
        }

        return ExplicitRenderRestoration(
            mainLine: { text, isTimedLine in
                restorer.restoreLine(
                    text,
                    lengthPreservingOnly: isTimedLine,
                    alternateLineSets: supportingLineSets
                )
            },
            translation: { text in
                restorer.restoreLexiconOnly(text, lengthPreservingOnly: false)
            }
        )
    }

    private func reload() {
        let entries = defaults[.lyricsExplicitLexiconEntries] ?? []
        if entries != cachedLexicon {
            cachedLexicon = entries
            cachedRestorer = ExplicitWordRestorer(words: entries)
        }
        changeSubject.send(())
    }
}
