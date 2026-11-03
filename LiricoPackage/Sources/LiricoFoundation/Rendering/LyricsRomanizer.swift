import Foundation

/// Romanized text, and how positions in it relate to the source line.
public struct RomanizedText: Equatable, Sendable {
    public let text: String
    /// UTF-16 positions in the source and in `text`, both increasing.
    let anchors: [Anchor]

    struct Anchor: Equatable, Sendable {
        let source: Int
        let output: Int
    }

    /// Word timing points into the source line, so it has to be moved along with the text.
    public func outputOffset(forSourceOffset offset: Int) -> Int {
        guard let last = anchors.last, let first = anchors.first else { return 0 }
        if offset <= first.source { return first.output }
        if offset >= last.source { return last.output }
        let upper = anchors.firstIndex { $0.source >= offset } ?? anchors.count - 1
        let (a, b) = (anchors[upper - 1], anchors[upper])
        let fraction = Double(offset - a.source) / Double(b.source - a.source)
        return a.output + Int((fraction * Double(b.output - a.output)).rounded())
    }
}

/// Converts the parts of a line the user wants romanized, by script: Hangul is always Korean,
/// so a Korean verse in a Japanese song gets romanized too.
public enum LyricsRomanizer {
    /// Returns nil when the line stays as it is.
    public static func romanize(_ line: String, reading: LyricsReading, lyricsLanguage: String?) -> RomanizedText? {
        let runs = scriptRuns(in: line)
        let hasKana = line.unicodeScalars.contains(where: isKana)
        let isJapanese = hasKana || lyricsLanguage?.hasPrefix("ja") == true

        var builder = Builder()
        var changed = false
        for run in runs {
            let pieces: [Piece]?
            switch run.script {
            case .hangul where reading.korean == .romanized:
                pieces = KoreanRomanizer.romanize(run.text).map { Piece(text: $0.text, sourceLength: $0.sourceLength, joinsPrevious: true) }
            case .cjk where isJapanese && reading.japanese == .romanized:
                pieces = japanesePieces(run.text)
            case .cjk where !isJapanese && reading.chinesePinyin && lyricsLanguage?.hasPrefix("zh") == true:
                pieces = pinyinPieces(run.text)
            default:
                pieces = nil
            }
            if let pieces {
                changed = true
                builder.appendRomanized(pieces)
            } else {
                builder.appendVerbatim(run.text)
            }
        }
        return changed ? builder.finish() : nil
    }

    // MARK: - Scripts

    private enum Script {
        case hangul, cjk, other
    }

    private struct ScriptRun {
        let script: Script
        var text: String
    }

    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3041 ... 0x309F, 0x30A1 ... 0x30FF, 0x31F0 ... 0x31FF, 0xFF66 ... 0xFF9F: true
        default: false
        }
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3005, 0x3007, 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xF900 ... 0xFAFF, 0x20000 ... 0x3FFFF: true
        default: false
        }
    }

    private static func scriptRuns(in line: String) -> [ScriptRun] {
        var runs: [ScriptRun] = []
        for scalar in line.unicodeScalars {
            let script: Script
            if KoreanRomanizer.isHangul(scalar) {
                script = .hangul
            } else if isKana(scalar) || isHan(scalar) {
                script = .cjk
            } else {
                script = .other
            }
            if runs.last?.script == script {
                runs[runs.count - 1].text.unicodeScalars.append(scalar)
            } else {
                runs.append(ScriptRun(script: script, text: String(scalar)))
            }
        }
        return runs
    }

    // MARK: - Tokenizer

    private struct Piece {
        let text: String
        let sourceLength: Int
        /// Syllables of one word run together; tokenizer words get a space between them.
        var joinsPrevious = false
    }

    /// Readings where the tokenizer gives the written form rather than the sung one.
    private static let japaneseCorrections = [
        "は": "wa",
        "へ": "e",
        "を": "o",
        "私": "watashi",
        "こんにちは": "kon'nichiwa",
        "こんばんは": "konbanwa",
        "ー": "-",
    ]

    private static func japanesePieces(_ run: String) -> [Piece] {
        tokenPieces(run, source: run, locale: "ja") { token, reading in
            // The tokenizer writes a lone っ as ~tsu.
            japaneseCorrections[token] ?? reading.replacingOccurrences(of: "~", with: "")
        }
    }

    private static func pinyinPieces(_ run: String) -> [Piece] {
        // macOS reads Traditional text one character at a time (音樂 as yīn lè), so it reads
        // the Simplified form. Keeping the length keeps tokens in line with the source.
        let simplified = run.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false)
        let tokenized = simplified.flatMap { $0.utf16.count == run.utf16.count ? $0 : nil } ?? run
        return tokenPieces(tokenized, source: run, locale: "zh-Hans") { _, reading in reading }
    }

    /// `text` is what gets tokenized, and `source` shows through where a token has no reading.
    private static func tokenPieces(
        _ text: String,
        source: String,
        locale: String,
        reading transform: (_ token: String, _ reading: String) -> String
    ) -> [Piece] {
        let nsText = text as NSString
        let nsSource = source as NSString
        let tokenizer = CFStringTokenizerCreate(
            nil, text as CFString, CFRange(location: 0, length: nsText.length),
            kCFStringTokenizerUnitWord, Locale(identifier: locale) as CFLocale
        )
        var pieces: [Piece] = []
        var position = 0
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            if range.location > position {
                let gap = NSRange(location: position, length: range.location - position)
                pieces.append(Piece(text: nsSource.substring(with: gap), sourceLength: gap.length))
            }
            let nsRange = NSRange(location: range.location, length: range.length)
            let reading = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription
            ) as? String
            let piece = reading.map { transform(nsText.substring(with: nsRange), $0) } ?? nsSource.substring(with: nsRange)
            pieces.append(Piece(text: piece, sourceLength: range.length))
            position = range.location + range.length
        }
        if position < nsText.length {
            let rest = NSRange(location: position, length: nsText.length - position)
            pieces.append(Piece(text: nsSource.substring(with: rest), sourceLength: rest.length))
        }
        return pieces
    }

    // MARK: - Assembly

    private struct Builder {
        private var output = ""
        private var outputLength = 0
        private var sourceLength = 0
        private var anchors: [RomanizedText.Anchor] = [.init(source: 0, output: 0)]
        private var lastWasRomanized = false

        mutating func appendVerbatim(_ text: String) {
            if lastWasRomanized { addWordGap(before: text) }
            append(text, sourceLength: text.utf16.count)
            lastWasRomanized = false
        }

        mutating func appendRomanized(_ pieces: [Piece]) {
            for (index, piece) in pieces.enumerated() where !piece.text.isEmpty || piece.sourceLength > 0 {
                if index == 0 || !piece.joinsPrevious { addWordGap(before: piece.text) }
                append(piece.text, sourceLength: piece.sourceLength)
            }
            lastWasRomanized = true
        }

        mutating func finish() -> RomanizedText {
            RomanizedText(text: output, anchors: anchors)
        }

        /// Romanized words need spaces that Hangul and kanji don't: Baby사랑해 is `Baby saranghae`.
        private mutating func addWordGap(before text: String) {
            guard let last = output.unicodeScalars.last, let first = text.unicodeScalars.first,
                  CharacterSet.alphanumerics.contains(last), CharacterSet.alphanumerics.contains(first) else {
                return
            }
            output.append(" ")
            outputLength += 1
            // The word starts after the gap, so a timing point on it mustn't land on the space.
            if anchors.last?.source == sourceLength {
                anchors[anchors.count - 1] = .init(source: sourceLength, output: outputLength)
            } else {
                anchors.append(.init(source: sourceLength, output: outputLength))
            }
        }

        private mutating func append(_ text: String, sourceLength length: Int) {
            output.append(text)
            outputLength += text.utf16.count
            sourceLength += length
            anchors.append(.init(source: sourceLength, output: outputLength))
        }
    }
}
