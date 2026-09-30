import Foundation
import Testing
@testable import LiricoFoundation

private func lyrics(_ body: String) -> Lyrics {
    Lyrics("[ti:song]\n[ar:artist]\n" + body)!
}

private func translated(_ lyrics: Lyrics, _ translations: [String], languageCode: String?) -> Lyrics {
    for (index, translation) in translations.enumerated() {
        lyrics.lines[index].attachments[.translation(languageCode: languageCode)] = translation
    }
    lyrics.metadata.attachmentTags.insert(.translation(languageCode: languageCode))
    return lyrics
}

private func upper(_ text: String) -> String { text.uppercased() }

@Suite("Line rendering")
struct LineRendererTests {
    @Test func restorationSeesTheSourceTextBeforeConversion() {
        let line = lyrics("[00:01.000]f*** it").lines[0]
        let restore = ExplicitRenderRestoration(
            mainLine: { text, _ in text.replacingOccurrences(of: "f***", with: "fuck") },
            translation: { $0 }
        )
        let rendered = LineRenderer.render(
            line: line, lyricsLanguage: "zh-Hans", translationLanguageCode: nil, converter: upper, restoreExplicit: restore
        )
        #expect(rendered.content == "FUCK IT")
    }

    @Test func onlyChinesePartsAreConverted() {
        let doc = translated(lyrics("[00:01.000]hello"), ["你好"], languageCode: "zh-Hans")
        let rendered = LineRenderer.render(
            line: doc.lines[0], lyricsLanguage: "en", translationLanguageCode: "zh-Hans", converter: { "[\($0)]" }
        )
        #expect(rendered.content == "hello")
        #expect(rendered.translation == "[你好]")
    }

    @Test func timedLinesAskForLengthPreservingRestoration() {
        let doc = lyrics("[00:01.000]one two\n[00:01.000][tt]<0,0><500,3>\n[00:05.000]plain")
        var timedFlags: [Bool] = []
        let restore = ExplicitRenderRestoration(mainLine: { text, timed in timedFlags.append(timed); return text }, translation: { $0 })
        for line in doc.lines {
            _ = LineRenderer.render(line: line, lyricsLanguage: nil, translationLanguageCode: nil, converter: nil, restoreExplicit: restore)
        }
        #expect(timedFlags == [true, false])
    }
}

@Suite("Language recognition")
struct LanguageRecognitionTests {
    @Test func anUntaggedTranslationIsTaggedWithItsLanguage() {
        let doc = translated(
            lyrics("[00:01.000]I walk alone through the empty streets tonight\n[00:05.000]and nobody knows my name"),
            ["今晚我独自走过空荡荡的街道", "没有人知道我的名字"],
            languageCode: nil
        )
        doc.recognizeLanguage()
        #expect(doc.metadata.language == "en")
        let code = doc.metadata.translationLanguages.first
        #expect(code?.hasPrefix("zh") == true)
        #expect(doc.lines[0].attachments[.translation(languageCode: code)] == "今晚我独自走过空荡荡的街道")
        #expect(doc.lines[0].attachments[.translation()] == nil)
    }
}

@Suite("Apple Music export")
struct AppleMusicExportTests {
    private let doc = translated(lyrics("[00:01.000]one\n[00:05.000]two"), ["uno", "dos"], languageCode: "es")

    @Test func translationsFollowTheirLinesOnlyWhenAskedFor() {
        #expect(AppleMusicExport.text(for: doc, plainLRC: false, includeTranslation: true, converter: nil) == "one\nuno\ntwo\ndos")
        #expect(AppleMusicExport.text(for: doc, plainLRC: false, includeTranslation: false, converter: nil) == "one\ntwo")
    }

    @Test func plainLRCIsOneLinePerTimestampWhateverTheTranslationSetting() {
        let text = AppleMusicExport.text(for: doc, plainLRC: true, includeTranslation: false, converter: nil)
        #expect(text.hasSuffix("[00:01.000]one【uno】\n[00:05.000]two【dos】"))
        #expect(text == AppleMusicExport.text(for: doc, plainLRC: true, includeTranslation: true, converter: nil))
    }

    @Test func runsOfBlankLinesCollapseToOne() {
        let gappy = lyrics("[00:01.000]one\n[00:02.000]\n[00:03.000]\n[00:04.000]\n[00:05.000]two")
        let text = AppleMusicExport.text(for: gappy, plainLRC: false, includeTranslation: false, converter: nil)
        #expect(text == "one\n\ntwo")
    }
}
