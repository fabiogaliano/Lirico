import Foundation

/// Romanizes Hangul by sound, following the Revised Romanization of Korean: 같이 is `gachi`.
///
/// Rules see only spelling, so changes that depend on word meaning can't be applied: inserted
/// ㄴ (한여름 stays `hanyeoreum`) and the exception that leaves ㅎ unmerged in nouns (묵호).
public enum KoreanRomanizer {
    /// The romanization of one run of source text, so callers can map positions within it.
    public struct Piece: Equatable, Sendable {
        public let text: String
        public let sourceLength: Int
    }

    /// One unbroken run of Hangul in a line.
    public struct Run: Equatable, Sendable {
        public let range: NSRange
        public let text: String
    }

    public static func isHangul(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100 ... 0x11FF, 0x3131 ... 0x318E, 0xA960 ... 0xA97C, 0xAC00 ... 0xD7A3, 0xD7B0 ... 0xD7FB:
            return true
        default:
            return false
        }
    }

    /// Every run of Hangul in `line`, with its romanization.
    public static func runs(in line: String) -> [Run] {
        var runs: [Run] = []
        var offset = 0
        var runStart: Int?
        var run = ""
        func finishRun() {
            guard let start = runStart else { return }
            runs.append(Run(
                range: NSRange(location: start, length: offset - start),
                text: romanize(run).map(\.text).joined()
            ))
            runStart = nil
            run = ""
        }
        for scalar in line.unicodeScalars {
            if isHangul(scalar) {
                if runStart == nil { runStart = offset }
                run.unicodeScalars.append(scalar)
            } else {
                finishRun()
            }
            offset += UTF16.width(scalar)
        }
        finishRun()
        return runs
    }

    /// Romanizes a run of Hangul. Sound changes only apply inside the run, since a space
    /// between words is also a pause in the rules this follows.
    public static func romanize(_ run: String) -> [Piece] {
        let composed = run.precomposedStringWithCanonicalMapping
        // Decomposed input loses its per-syllable correspondence with the source.
        let isOneToOne = composed.utf16.count == run.utf16.count

        let scalars = Array(composed.unicodeScalars)
        var pieces: [Piece] = []
        var onset: Int?
        var previousCoda = Coda.none
        for (index, scalar) in scalars.enumerated() {
            guard let syllable = Syllable(scalar) else {
                pieces.append(Piece(text: looseJamo(scalar), sourceLength: UTF16.width(scalar)))
                onset = nil
                previousCoda = .none
                continue
            }
            let next = index + 1 < scalars.count ? Syllable(scalars[index + 1]) : nil
            let change = next.map { soundChange(final: syllable.final, onset: $0.onset, nextVowel: $0.vowel) }
            let coda = change?.coda ?? neutralized(syllable.final)
            var text = onsetText(onset ?? syllable.onset, afterCoda: previousCoda)
            text += vowels[syllable.vowel]
            text += coda.rawValue
            pieces.append(Piece(text: text, sourceLength: 1))
            onset = change?.onset
            previousCoda = coda
        }
        guard isOneToOne else {
            return [Piece(text: pieces.map(\.text).joined(), sourceLength: run.utf16.count)]
        }
        return pieces
    }

    // MARK: - Hangul structure

    private struct Syllable {
        let onset: Int
        let vowel: Int
        let final: Int

        init?(_ scalar: Unicode.Scalar) {
            guard (0xAC00 ... 0xD7A3).contains(scalar.value) else { return nil }
            let index = Int(scalar.value) - 0xAC00
            onset = index / 588
            vowel = index % 588 / 28
            final = index % 28
        }
    }

    /// Positions in the Unicode order of syllable-initial consonants.
    private enum Onset {
        static let g = 0, kk = 1, n = 2, d = 3, r = 5, m = 6, b = 7, s = 9, ss = 10
        static let silent = 11, j = 12, ch = 14, k = 15, t = 16, p = 17, h = 18
    }

    /// Positions in the Unicode order of syllable-final consonants.
    private enum Final {
        static let none = 0, g = 1, kk = 2, gs = 3, n = 4, nj = 5, nh = 6, d = 7, l = 8, lg = 9, lm = 10
        static let lb = 11, ls = 12, lt = 13, lp = 14, lh = 15, m = 16, b = 17, bs = 18, s = 19, ss = 20
        static let ng = 21, j = 22, ch = 23, k = 24, t = 25, p = 26, h = 27
    }

    private static let vowelI = 20
    private static let vowelYeo = 6

    private static let onsets = ["g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "", "j", "jj", "ch", "k", "t", "p", "h"]
    private static let vowels = [
        "a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae",
        "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i",
    ]
    /// U+3131 to U+3163: consonants and vowels typed on their own, like ㅋㅋㅋ.
    private static let jamo = [
        "g", "kk", "gs", "n", "nj", "nh", "d", "tt", "r", "lg", "lm", "lb", "ls", "lt", "lp", "lh",
        "m", "b", "pp", "bs", "s", "ss", "ng", "j", "jj", "ch", "k", "t", "p", "h",
        "a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae",
        "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i",
    ]

    private static func looseJamo(_ scalar: Unicode.Scalar) -> String {
        let value = Int(scalar.value)
        guard (0x3131 ... 0x3163).contains(value) else { return String(scalar) }
        return jamo[value - 0x3131]
    }

    /// The seven sounds a syllable can end in.
    private enum Coda: String {
        case none = "", k, n, t, l, m, p, ng
    }

    private static func onsetText(_ onset: Int, afterCoda coda: Coda) -> String {
        onset == Onset.r && coda == .l ? "l" : onsets[onset]
    }

    private static func neutralized(_ final: Int) -> Coda {
        switch final {
        case Final.none: .none
        case Final.g, Final.kk, Final.gs, Final.lg, Final.k: .k
        case Final.n, Final.nj, Final.nh: .n
        case Final.d, Final.s, Final.ss, Final.j, Final.ch, Final.t, Final.h: .t
        case Final.l, Final.lb, Final.ls, Final.lt, Final.lh: .l
        case Final.m, Final.lm: .m
        case Final.b, Final.bs, Final.p, Final.lp: .p
        default: .ng
        }
    }

    // MARK: - Sound changes

    /// What a syllable's final consonant and the next syllable's first consonant become.
    private static func soundChange(final: Int, onset: Int, nextVowel: Int) -> (coda: Coda, onset: Int) {
        if onset == Onset.silent { return beforeVowel(final: final, nextVowel: nextVowel) }
        if onset == Onset.h { return beforeH(final: final, nextVowel: nextVowel) }
        if final == Final.h || final == Final.nh || final == Final.lh { return afterH(final: final, onset: onset) }
        // ㄺ keeps ㄹ before ㄱ: 맑게 is malge, but 맑다 is makda.
        let coda = final == Final.lg && onset == Onset.g ? Coda.l : neutralized(final)
        return assimilated(coda: coda, onset: onset)
    }

    /// The final consonant moves across to fill the empty onset: 있어 is isseo.
    private static func beforeVowel(final: Int, nextVowel: Int) -> (coda: Coda, onset: Int) {
        if nextVowel == vowelI {
            // Palatalization: 같이 is gachi, 해돋이 is haedoji.
            switch final {
            case Final.d: return (.none, Onset.j)
            case Final.t: return (.none, Onset.ch)
            case Final.lt: return (.l, Onset.ch)
            default: break
            }
        }
        switch final {
        case Final.none: return (.none, Onset.silent)
        case Final.ng: return (.ng, Onset.silent)
        case Final.h: return (.none, Onset.silent)
        case Final.nh: return (.none, Onset.n)
        case Final.lh: return (.none, Onset.r)
        case Final.gs: return (.k, Onset.s)
        case Final.nj: return (.n, Onset.j)
        case Final.lg: return (.l, Onset.g)
        case Final.lm: return (.l, Onset.m)
        case Final.lb: return (.l, Onset.b)
        case Final.ls: return (.l, Onset.s)
        case Final.lt: return (.l, Onset.t)
        case Final.lp: return (.l, Onset.p)
        case Final.bs: return (.p, Onset.s)
        case Final.g: return (.none, Onset.g)
        case Final.kk: return (.none, Onset.kk)
        case Final.n: return (.none, Onset.n)
        case Final.d: return (.none, Onset.d)
        case Final.l: return (.none, Onset.r)
        case Final.m: return (.none, Onset.m)
        case Final.b: return (.none, Onset.b)
        case Final.s: return (.none, Onset.s)
        case Final.ss: return (.none, Onset.ss)
        case Final.j: return (.none, Onset.j)
        case Final.ch: return (.none, Onset.ch)
        case Final.k: return (.none, Onset.k)
        case Final.t: return (.none, Onset.t)
        case Final.p: return (.none, Onset.p)
        default: return (neutralized(final), Onset.silent)
        }
    }

    /// ㄱ, ㄷ, ㅂ and ㅈ merge with a following ㅎ: 잡혀 is japyeo, 굳히다 is guchida.
    private static func beforeH(final: Int, nextVowel: Int) -> (coda: Coda, onset: Int) {
        let palatal = nextVowel == vowelI || nextVowel == vowelYeo
        switch final {
        case Final.g, Final.k, Final.kk: return (.none, Onset.k)
        case Final.b, Final.p: return (.none, Onset.p)
        case Final.j, Final.ch: return (.none, Onset.ch)
        case Final.d, Final.t, Final.s, Final.ss: return (.none, palatal && final != Final.s && final != Final.ss ? Onset.ch : Onset.t)
        case Final.lg: return (.l, Onset.k)
        case Final.lb: return (.l, Onset.p)
        case Final.nj: return (.n, Onset.ch)
        default: return (neutralized(final), Onset.h)
        }
    }

    /// A final ㅎ merges with ㄱ, ㄷ and ㅈ, and turns into ㄴ before ㄴ: 좋고 is joko, 놓는 is nonneun.
    private static func afterH(final: Int, onset: Int) -> (coda: Coda, onset: Int) {
        let remainder: Coda = final == Final.nh ? .n : final == Final.lh ? .l : .none
        switch onset {
        case Onset.g: return (remainder, Onset.k)
        case Onset.d: return (remainder, Onset.t)
        case Onset.j: return (remainder, Onset.ch)
        case Onset.s: return (remainder, Onset.s)
        case Onset.n:
            if final == Final.lh { return (.l, Onset.r) }
            return (.n, Onset.n)
        default:
            return assimilated(coda: neutralized(final), onset: onset)
        }
    }

    /// Neighboring consonants become more alike: 백마 is baengma, 독립 is dongnip, 신라 is silla.
    private static func assimilated(coda: Coda, onset: Int) -> (coda: Coda, onset: Int) {
        switch onset {
        case Onset.r:
            switch coda {
            case .k, .ng: return (.ng, Onset.n)
            case .t: return (.n, Onset.n)
            case .p, .m: return (.m, Onset.n)
            case .n, .l: return (.l, Onset.r)
            case .none: return (.none, onset)
            }
        case Onset.n:
            if coda == .l { return (.l, Onset.r) }
            return (nasalized(coda), onset)
        case Onset.m:
            return (nasalized(coda), onset)
        default:
            return (coda, onset)
        }
    }

    private static func nasalized(_ coda: Coda) -> Coda {
        switch coda {
        case .k: .ng
        case .t: .n
        case .p: .m
        default: coda
        }
    }
}
