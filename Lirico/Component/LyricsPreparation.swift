import LiricoFoundation

/// Runs the two-step "make a Lyrics object ready for display" pipeline on every
/// ingress path: apply the user's block-list filter, then detect the dominant
/// language of the content and any translation attachment.
///
/// Owns a `LyricsFilter` instance so the predicate's lifecycle is anchored at
/// `AppContainer` construction rather than triggered lazily on first call.
final class LyricsPreparation {
    private let filter: LyricsFilter

    init(filter: LyricsFilter) {
        self.filter = filter
    }

    /// Filter and language-detect `lyrics` in place so it is ready for display.
    func prepare(_ lyrics: Lyrics) {
        filter.apply(to: lyrics)
        lyrics.recognizeLanguage()
    }
}
