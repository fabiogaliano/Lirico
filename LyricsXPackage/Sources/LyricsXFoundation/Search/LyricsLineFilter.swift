import Foundation
@preconcurrency import LyricsKit

/// Builds the line-keep predicate used to filter junk/metadata lines out of a
/// `Lyrics` object: a line is kept only when it matches **none** of the filter
/// keys.
///
/// - `/`-prefixed keys are treated as regular expressions.
/// - All other keys are literal substrings (`.ignoreMetacharacters`).
///
/// Matching is case-sensitive and searches anywhere in the line — the same
/// configuration the app's `LyricsFilter` uses. (That type's `Regex` dependency
/// is a thin `NSRegularExpression` wrapper, so building with `NSRegularExpression`
/// here is behaviorally identical.) Sharing this builder means the app and the
/// `lyrics-diag` tool filter lines by one definition.
///
/// Apply the result with `Lyrics.filtrate(isIncluded:)`, which disables
/// (not deletes) non-matching lines.
public func makeLyricsFilterPredicate(keys: [String], enabled: Bool) -> NSPredicate {
    guard enabled else { return NSCompoundPredicate(andPredicateWithSubpredicates: []) }
    let subpredicates: [NSPredicate] = keys.compactMap { key in
        let isRegex = key.hasPrefix("/")
        let pattern = isRegex ? String(key.dropFirst()) : key
        let options: NSRegularExpression.Options = isRegex ? [] : [.ignoreMetacharacters]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        return NSPredicate { object, _ in
            guard let line = object as? LyricsLine else { return false }
            let range = NSRange(line.content.startIndex..., in: line.content)
            return regex.firstMatch(in: line.content, options: [], range: range) == nil
        }
    }
    return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
}
