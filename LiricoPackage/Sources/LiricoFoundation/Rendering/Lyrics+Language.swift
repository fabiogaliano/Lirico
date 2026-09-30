import Foundation

extension Lyrics {
    /// Records the dominant language of the lyrics, and tags an untagged translation with
    /// its own language so renderers can decide per part whether Chinese conversion applies.
    public func recognizeLanguage() {
        var lyricsContent = ""
        var translationContent = ""
        for line in lines {
            lyricsContent += line.content
            if let trans = line.attachments.translation() {
                translationContent += trans
            }
        }
        metadata.language = dominantLanguage(of: lyricsContent)
        if let transLan = dominantLanguage(of: translationContent) {
            let tag = LyricsLine.Attachments.Tag.translation(languageCode: transLan)
            guard !metadata.attachmentTags.contains(tag) else {
                return
            }
            for idx in lines.indices {
                if let trans = lines[idx].attachments.translation() {
                    lines[idx].attachments[.translation()] = nil
                    lines[idx].attachments[.translation(languageCode: transLan)] = trans
                }
            }
            metadata.attachmentTags.insert(tag)
        }
    }
}

private func dominantLanguage(of text: String) -> String? {
    let string = text as CFString
    return CFStringTokenizerCopyBestStringLanguage(string, CFRange(location: 0, length: CFStringGetLength(string))) as String?
}
