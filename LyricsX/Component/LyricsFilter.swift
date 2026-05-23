import Foundation
import GenericID
import LyricsXFoundation
import Regex

/// Compiles the user's lyrics block-list into a predicate and applies it to a
/// `Lyrics` object. Owned by `LyricsPreparation` (via `AppContainer`) so the
/// observer lifecycle matches the rest of the composition root.
///
/// Filter key semantics (preserved from the previous static implementation):
///   - keys starting with `/` are interpreted as regex patterns,
///   - non-regex keys ignore regex metacharacters,
///   - keys that fail to compile are silently dropped,
///   - `LyricsLine.enabled` is set to `false` for any line whose content
///     matches at least one predicate (i.e. the line is kept but hidden).
final class LyricsFilter {
    private let defaults: UserDefaults
    private var predicate: NSPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [])
    private var observation: (any DefaultsObservation)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        observation = defaults.observe(keys: [.lyricsFilterEnabled, .lyricsFilterKeys], options: [.new, .initial]) { [weak self] in
            self?.rebuild()
        }
    }

    /// Apply the current filter to `lyrics` in place.
    func apply(to lyrics: Lyrics) {
        lyrics.filtrate(isIncluded: predicate)
    }

    private func rebuild() {
        guard defaults[.lyricsFilterEnabled] else {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [])
            return
        }

        let predicates = defaults[.lyricsFilterKeys].compactMap { (key: String) -> NSPredicate? in
            let isRegex = key.hasPrefix("/")
            let pattern = isRegex ? String(key.dropFirst()) : key
            let options: NSRegularExpression.Options = isRegex ? [] : [.ignoreMetacharacters]
            guard let regex = try? Regex(pattern, options: options) else { return nil }
            return NSPredicate { object, _ in
                guard let object = object as? LyricsLine else { return false }
                return !regex.isMatch(object.content)
            }
        }
        predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
}
