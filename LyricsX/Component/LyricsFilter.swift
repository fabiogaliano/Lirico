import Foundation
import GenericID
import LyricsXFoundation

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
        // Predicate construction lives in `LyricsXFoundation` (`makeLyricsFilterPredicate`)
        // so the app and out-of-app tooling filter lines by one definition.
        let newPredicate = makeLyricsFilterPredicate(
            keys: defaults[.lyricsFilterKeys],
            enabled: defaults[.lyricsFilterEnabled]
        )

        lock.lock()
        predicate = newPredicate
        lock.unlock()
    }
}
