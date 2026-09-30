import Combine
import Foundation
import GenericID
import LiricoFoundation

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

// MARK: - ExplicitLyricsResolver

/// App-side adapter between the explicit-restoration preferences and the pure
/// `ExplicitWordRestorer`. Owns the cached restorer and rebuilds it when the
/// lexicon entries change.
final class ExplicitLyricsResolver {
    private let defaults: UserDefaults
    /// The display coordinator builds restorations on its background queue while
    /// lexicon edits rebuild the restorer on main, so shared state sits behind a lock.
    private let lock = NSLock()
    private var cachedRestorer: ExplicitWordRestorer
    private var cachedLexicon: [String]
    /// Supporting candidates only change per track or search, but restorations are
    /// rebuilt on every line change; reuse their extracted lines.
    private var cachedSupporting: [Lyrics] = []
    private var cachedSupportingLineSets: [[String]] = []
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

    private var isEnabled: Bool {
        defaults[.lyricsExplicitRestorationEnabled]
    }

    /// Emits when the enablement flag or lexicon entries change, so display
    /// surfaces can recompute visible text without reloading lyrics.
    var settingsDidChange: AnyPublisher<Void, Never> {
        changeSubject.eraseToAnyPublisher()
    }

    /// Builds the display-time restorers bound to `context`. Returns identity
    /// closures when the feature is disabled, so call sites stay branch-free.
    func makeRenderRestoration(context: ExplicitRestorationContext) -> ExplicitRenderRestoration {
        guard isEnabled else { return .identity }

        let (restorer, supportingLineSets) = lock.withLock {
            (cachedRestorer, candidateLineSets(for: context.supportingCandidates))
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

    /// Must be called with `lock` held.
    private func candidateLineSets(for candidates: [Lyrics]) -> [[String]] {
        // Identity, held strongly so a freed candidate's address can't alias a new one.
        let unchanged = candidates.count == cachedSupporting.count
            && zip(candidates, cachedSupporting).allSatisfy { $0 === $1 }
        if !unchanged {
            cachedSupporting = candidates
            cachedSupportingLineSets = candidates.map { lyrics in
                lyrics.lines
                    .filter { $0.enabled && !$0.content.isEmpty }
                    .map(\.content)
            }
        }
        return cachedSupportingLineSets
    }

    private func reload() {
        let entries = defaults[.lyricsExplicitLexiconEntries] ?? []
        lock.withLock {
            if entries != cachedLexicon {
                cachedLexicon = entries
                cachedRestorer = ExplicitWordRestorer(words: entries)
            }
        }
        changeSubject.send(())
    }
}
