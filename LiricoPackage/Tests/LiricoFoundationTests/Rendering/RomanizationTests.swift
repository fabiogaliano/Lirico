import Foundation
import Testing
@testable import LiricoFoundation

private func korean(_ text: String) -> String {
    LyricsRomanizer.romanize(text, reading: LyricsReading(korean: .romanized), lyricsLanguage: "ko")?.text ?? text
}

private func japanese(_ text: String) -> String {
    LyricsRomanizer.romanize(text, reading: LyricsReading(japanese: .romanized), lyricsLanguage: "ja")?.text ?? text
}

private func pinyin(_ text: String) -> String {
    LyricsRomanizer.romanize(text, reading: LyricsReading(chinesePinyin: true), lyricsLanguage: "zh-Hans")?.text ?? text
}

@Suite("Korean romanization")
struct KoreanRomanizerTests {
    /// The examples published with the official rules.
    @Test(arguments: [
        ("백마", "baengma"), ("종로", "jongno"), ("왕십리", "wangsimni"), ("별내", "byeollae"), ("신라", "silla"),
        ("해돋이", "haedoji"), ("같이", "gachi"), ("굳히다", "guchida"),
        ("좋고", "joko"), ("놓다", "nota"), ("잡혀", "japyeo"), ("낳지", "nachi"),
        ("압구정", "apgujeong"), ("낙동강", "nakdonggang"), ("샛별", "saetbyeol"), ("울산", "ulsan"),
    ])
    func officialExamples(hangul: String, expected: String) {
        #expect(korean(hangul) == expected)
    }

    @Test(arguments: [
        ("사랑해", "saranghae"), ("감사합니다", "gamsahamnida"), ("독립", "dongnip"), ("먹는", "meongneun"),
        ("국물", "gungmul"), ("닫는", "danneun"), ("놓는", "nonneun"), ("한국어", "hangugeo"),
        ("좋아", "joa"), ("않아", "ana"), ("괜찮아", "gwaenchana"), ("잃어", "ireo"), ("많이", "mani"),
        ("읽어", "ilgeo"), ("없어", "eopseo"), ("맞아", "maja"), ("있어줘", "isseojwo"), ("있는", "inneun"),
        ("없는", "eomneun"), ("읽는", "ingneun"), ("맑게", "malge"), ("별빛이", "byeolbichi"), ("곁에", "gyeote"),
        ("걸으면서", "georeumyeonseo"), ("밖에", "bakke"), ("달리다", "dallida"), ("심리", "simni"),
        ("축하해", "chukahae"), ("못해", "motae"), ("앉아", "anja"), ("값은", "gapseun"), ("강아지", "gangaji"),
    ])
    func commonLyricWords(hangul: String, expected: String) {
        #expect(korean(hangul) == expected)
    }

    @Test func aSpaceEndsSoundChanges() {
        #expect(korean("너를 사랑해") == "neoreul saranghae")
        #expect(korean("옷 입어") == "ot ibeo")
    }

    @Test func otherTextStaysAsItIs() {
        #expect(korean("Baby 사랑해!") == "Baby saranghae!")
        #expect(korean("Baby사랑해") == "Baby saranghae")
        #expect(korean("사랑해baby") == "saranghae baby")
        #expect(korean("같이, 가요") == "gachi, gayo")
    }

    @Test func consonantsTypedOnTheirOwnAreRomanizedToo() {
        #expect(korean("ㅋㅋㅋ") == "kkk")
    }

    @Test func decomposedHangulStillReadsCorrectly() {
        #expect(korean("같이".decomposedStringWithCanonicalMapping) == "gachi")
    }

    @Test func runsReportWhereHangulIs() {
        let runs = KoreanRomanizer.runs(in: "Baby 사랑해 같이")
        #expect(runs.map(\.text) == ["saranghae", "gachi"])
        #expect(runs.map(\.range) == [NSRange(location: 5, length: 3), NSRange(location: 9, length: 2)])
    }
}

@Suite("Japanese and Chinese romanization")
struct TokenizerRomanizationTests {
    @Test func particlesReadAsTheyAreSung() {
        #expect(japanese("今夜は一緒にいて") == "kon'ya wa issho ni i te")
        #expect(japanese("夢を見た") == "yume o mi ta")
        #expect(japanese("東京へ行く").hasSuffix("e iku"))
    }

    @Test func kanaDecidesALineIsJapaneseWhateverTheSongIs() {
        let reading = LyricsReading(japanese: .romanized, chinesePinyin: true)
        #expect(LyricsRomanizer.romanize("君が好き", reading: reading, lyricsLanguage: "zh-Hans")?.text == "kimi ga suki")
    }

    @Test func kanjiFollowsTheLanguageOfTheSong() {
        #expect(LyricsRomanizer.romanize("音楽", reading: LyricsReading(chinesePinyin: true), lyricsLanguage: "ja") == nil)
    }

    @Test func pinyinReadsWholeWords() {
        #expect(pinyin("银行") == "yínháng")
        #expect(pinyin("音乐") == "yīnyuè")
        #expect(pinyin("今晚留在我身边") == "jīnwǎn liú zài wǒ shēnbiān")
    }

    @Test func traditionalTextGetsTheSamePinyin() {
        #expect(pinyin("音樂") == "yīnyuè")
        #expect(pinyin("銀行") == "yínháng")
    }

    @Test func aKoreanVerseIsRomanizedInASongInAnotherLanguage() {
        let reading = LyricsReading(korean: .romanized)
        #expect(LyricsRomanizer.romanize("사랑해", reading: reading, lyricsLanguage: "ja")?.text == "saranghae")
    }

    @Test func nothingChangesWithTheOriginalReading() {
        for line in ["사랑해", "今夜は", "我爱你", "hello"] {
            #expect(LyricsRomanizer.romanize(line, reading: .original, lyricsLanguage: "ko") == nil)
        }
    }

    @Test func annotatedKoreanLeavesTheTextForTheLabelToDraw() {
        #expect(LyricsRomanizer.romanize("사랑해", reading: LyricsReading(korean: .annotated), lyricsLanguage: "ko") == nil)
        #expect(LyricsReading(korean: .annotated).withoutAnnotations.korean == .romanized)
    }
}

@Suite("Word timing on romanized lines")
struct RomanizedTimingTests {
    private let reading = LyricsReading(korean: .romanized)

    private func line(_ body: String) -> LyricsLine {
        Lyrics("[ti:song]\n[ar:artist]\n" + body)!.lines[0]
    }

    @Test func timingPointsStayOnTheirWords() throws {
        let timed = line("[00:01.000]오늘 밤 같이\n[00:01.000][tt]<0,0><500,3><900,5><1200,7>")
        let rendered = LineRenderer.renderForDisplay(
            line: timed, lyricsLanguage: "ko", translationLanguageCode: nil, converter: nil, reading: reading
        )
        #expect(rendered.content == "oneul bam gachi")
        let tags = try #require(rendered.timetag?.tags)
        #expect(tags.map(\.index) == [0, 6, 10, 15])
        #expect(tags.map(\.time) == [0, 0.5, 0.9, 1.2])
    }

    @Test func timingPointsStayOnSyllables() throws {
        let timed = line("[00:01.000]사랑해\n[00:01.000][tt]<0,0><300,1><600,2><900,3>")
        let rendered = LineRenderer.renderForDisplay(
            line: timed, lyricsLanguage: "ko", translationLanguageCode: nil, converter: nil, reading: reading
        )
        #expect(rendered.timetag?.tags.map(\.index) == [0, 2, 6, 9])
    }

    @Test func aGapBeforeAWordIsNotPartOfIt() {
        let romanized = LyricsRomanizer.romanize("Baby사랑해", reading: reading, lyricsLanguage: "ko")
        #expect(romanized?.text == "Baby saranghae")
        #expect(romanized?.outputOffset(forSourceOffset: 4) == 5)
    }

    @Test func offsetsNeverGoBackwardsOrPastTheEnd() throws {
        let romanized = try #require(LyricsRomanizer.romanize("오늘 밤 Baby 같이 있어줘!", reading: reading, lyricsLanguage: "ko"))
        let offsets = (0 ... 30).map(romanized.outputOffset(forSourceOffset:))
        #expect(offsets == offsets.sorted())
        #expect(offsets.last == romanized.text.utf16.count)
    }

    @Test func untouchedLinesKeepTheirTiming() {
        let timed = line("[00:01.000]hello there\n[00:01.000][tt]<0,0><500,6>")
        let rendered = LineRenderer.renderForDisplay(
            line: timed, lyricsLanguage: "en", translationLanguageCode: nil, converter: nil, reading: reading
        )
        #expect(rendered.content == "hello there")
        #expect(rendered.timetag?.tags.map(\.index) == [0, 6])
    }
}

@Suite("Reading settings")
struct ReadingSettingsTests {
    @Test func oldSwitchesMapToOneChoice() {
        #expect(LyricsReading.Japanese.migrated(furigana: false, romaji: false) == .original)
        #expect(LyricsReading.Japanese.migrated(furigana: true, romaji: false) == .furigana)
        #expect(LyricsReading.Japanese.migrated(furigana: false, romaji: true) == .romanized)
        #expect(LyricsReading.Japanese.migrated(furigana: true, romaji: true) == .romanized)
    }

    @Test(arguments: [
        ("en", ChineseConversion.none), ("zh-Hans-CN", ChineseConversion.none),
        ("zh-Hant", ChineseConversion.traditional), ("zh-Hant-TW", ChineseConversion.traditionalTaiwan),
        ("zh-Hant-HK", ChineseConversion.traditionalHongKong), ("zh-Hant-MO", ChineseConversion.traditionalHongKong),
        ("zh-TW", ChineseConversion.traditionalTaiwan), ("yue-Hant-HK", ChineseConversion.traditionalHongKong),
    ])
    func chineseDefaultFollowsTheRegion(language: String, expected: Int) {
        #expect(ChineseConversion.defaultValue(forLanguage: language) == expected)
    }
}

@Suite("Apple Music export conversion")
struct AppleMusicExportConversionTests {
    private func document(_ language: String, translation: String, code: String) -> Lyrics {
        let doc = Lyrics("[ti:song]\n[ar:artist]\n[00:01.000]line")!
        doc.metadata.language = language
        doc.lines[0].attachments[.translation(languageCode: code)] = translation
        doc.metadata.attachmentTags.insert(.translation(languageCode: code))
        return doc
    }

    @Test func aChineseTranslationIsConvertedForASongInAnotherLanguage() {
        let text = AppleMusicExport.text(
            for: document("en", translation: "你好", code: "zh-Hans"),
            plainLRC: true, includeTranslation: true, converter: { "[\($0)]" }
        )
        #expect(text.hasSuffix("line【[你好]】"))
    }

    @Test func japaneseLyricsStayAsTheyAreBesideAChineseTranslation() {
        let text = AppleMusicExport.text(
            for: document("ja", translation: "你好", code: "zh-Hans"),
            plainLRC: true, includeTranslation: true, converter: { "[\($0)]" }
        )
        #expect(text.contains("]line【[你好]】"))
    }

    @Test func romanizationNeverReachesAnExport() {
        let doc = Lyrics("[ti:song]\n[ar:artist]\n[00:01.000]사랑해")!
        #expect(AppleMusicExport.text(for: doc, plainLRC: false, includeTranslation: false, converter: nil) == "사랑해")
    }
}
