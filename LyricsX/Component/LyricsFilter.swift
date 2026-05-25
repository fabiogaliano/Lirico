import Foundation
import GenericID
import LyricsXFoundation
import Regex

final class LyricsFilter {
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var predicate: NSPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [])
    private var observation: (any DefaultsObservation)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        observation = defaults.observe(keys: [.lyricsFilterEnabled, .lyricsFilterKeys], options: [.new, .initial]) { [weak self] in
            self?.rebuild()
        }
    }

    func apply(to lyrics: Lyrics) {
        lock.lock()
        let predicate = self.predicate
        lock.unlock()
        lyrics.filtrate(isIncluded: predicate)
    }

    private func rebuild() {
        let newPredicate: NSPredicate

        if defaults[.lyricsFilterEnabled] {
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
            newPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        } else {
            newPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [])
        }

        lock.lock()
        predicate = newPredicate
        lock.unlock()
    }
}
