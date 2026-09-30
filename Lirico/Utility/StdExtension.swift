import Foundation

extension Comparable {
    func clamped(to limit: ClosedRange<Self>) -> Self {
        return min(max(self, limit.lowerBound), limit.upperBound)
    }
}

// MARK: - Range

extension String {
    var fullRange: NSRange {
        return NSRange(location: 0, length: utf16.count)
    }
}

extension NSAttributedString {
    var fullRange: NSRange {
        return NSRange(location: 0, length: length)
    }
}

extension CharacterSet {
    static let hiragana = CharacterSet(charactersIn: "\u{3040}" ..< "\u{30a0}")
    static let katakana = CharacterSet(charactersIn: "\u{30a0}" ..< "\u{3100}")
    static let kanji = CharacterSet(charactersIn: "\u{4e00}" ..< "\u{9fc0}")
}
