import LyricsXFoundation

/// Encapsulates the two-step "make a Lyrics object ready for display" pipeline:
/// filter out lines matching the user's block-list, then detect the dominant language
/// of both the main content and any translation attachment.
///
/// Usage:
///   ```swift
///   LyricsPreparer.prepare(lyrics)
///   ```
enum LyricsPreparer {
    /// Filter and language-detect `lyrics` in place so it is ready for display.
    static func prepare(_ lyrics: Lyrics) {
        lyrics.filtrate()
        lyrics.recognizeLanguage()
    }
}
