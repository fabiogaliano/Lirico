import AppKit
import LiricoFoundation
import OpenCC

protocol ScrollLyricsViewDelegate: AnyObject {
    func doubleClickLyricsLine(at position: TimeInterval)
    func scrollWheelDidStartScroll()
    func scrollWheelDidEndScroll()
    /// A line was single-clicked while `clickToSyncEnabled`. Used by the sync
    /// panel to align this line to the current playback position.
    func syncToLyricsLine(at position: TimeInterval)
}

extension ScrollLyricsViewDelegate {
    // Default no-op so non-sync hosts (e.g. the HUD) needn't implement it.
    func syncToLyricsLine(at position: TimeInterval) {}
}

class ScrollLyricsView: NSScrollView {
    weak var delegate: ScrollLyricsViewDelegate?

    /// When true, a single click on a line reports `syncToLyricsLine(at:)`
    /// instead of being swallowed. The HUD leaves this off; the sync panel turns
    /// it on.
    var clickToSyncEnabled = false

    /// When true, a rounded box is drawn around the word currently being sung.
    /// The sync panel turns it on as word-level feedback for click-to-sync; the
    /// HUD leaves it off, since the karaoke fill alone shows word progress and the
    /// HUD never syncs by word.
    var showsWordBox = true {
        didSet { if !showsWordBox { hideWordBox() } }
    }

    private let displaySettings = DisplaySettings()

    private var textView: NSTextView {
        // swiftlint:disable:next force_cast
        return documentView as! NSTextView
    }

    var fadeStripWidth: CGFloat = 24

    @objc dynamic var textColor = #colorLiteral(red: 0.6, green: 0.6, blue: 0.6, alpha: 1) {
        didSet {
            DispatchQueue.main.async {
                let range = self.textView.string.fullRange
                self.textView.textStorage?.addAttribute(.foregroundColor, value: self.textColor, range: range)
                if let highlightedRange = self.highlightedRange {
                    self.textView.textStorage?.addAttribute(.foregroundColor, value: self.highlightColor, range: highlightedRange)
                }
            }
        }
    }

    @objc dynamic var highlightColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1) {
        didSet {
            guard let highlightedRange = self.highlightedRange else { return }
            DispatchQueue.main.async {
                self.textView.textStorage?.addAttribute(.foregroundColor, value: self.highlightColor, range: highlightedRange)
            }
        }
    }

    @objc dynamic var fontName = "SFProText-Regular" {
        didSet { updateFont() }
    }

    @objc dynamic var fontSize: CGFloat = 15 {
        didSet { updateFont() }
    }

    private struct RenderedLineRange {
        let lineIndex: Int
        let position: TimeInterval
        let range: NSRange
        /// UTF-16 length of just the primary (sung) text, excluding any appended
        /// translation. The karaoke fill clamps to this so a word fill never
        /// bleeds into the translation rendered on the line below.
        let mainContentLength: Int
        /// Word-level timing for this line, when present. Lets a click resolve to
        /// the exact word's time rather than the line's start (`position`).
        let timetag: LyricsLine.Attachments.InlineTimeTag?
    }

    private var ranges: [RenderedLineRange] = []
    private var highlightedRange: NSRange?

    /// While true, clip-view bounds changes are treated as our own programmatic
    /// scroll (from `scroll(lineIndex:)`) rather than the user dragging. Set for a
    /// short window around each auto-scroll so the follow animation doesn't read as
    /// "the user is browsing".
    private var suppressScrollDetection = false
    private var unsuppressWorkItem: DispatchWorkItem?
    private var boundsObserver: NSObjectProtocol?

    /// Karaoke "now" marker: a rounded box drawn around the word currently being
    /// sung. Lives inside the text view so it scrolls with the lyrics; hidden for
    /// lines without word timetags (the host shows its line-wide band instead).
    private lazy var wordBox: NSView = {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 5
        box.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        box.isHidden = true
        return box
    }()

    /// The character range the `wordBox` currently frames, to skip redundant
    /// reframing on the ~30Hz fill ticks when the sung word hasn't changed.
    private var wordBoxRange: NSRange?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installTextView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installTextView()
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    /// Build the non-editable, non-selectable `NSTextView` that backs this scroll
    /// view. This used to be supplied by `Main.storyboard`; when the UI moved to
    /// code (commit 511a7e6a) the document view was dropped, leaving the
    /// `documentView as! NSTextView` force-cast to crash on first access. Recreated
    /// here with the same configuration the storyboard declared.
    private func installTextView() {
        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = false
        usesPredominantAxisScrolling = false
        drawsBackground = false

        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        // Don't let the container's height follow the view; the view grows to fit
        // the text, not the other way around.
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        // A vertically-resizable text view only grows its frame up to `maxSize`.
        // Created programmatically, `maxSize` defaults to the (zero) frame size,
        // so the frame can't grow tall enough to hold all the glyphs and the
        // scroll view clamps short of the last lines — the storyboard set this to
        // a huge height (10000000) for exactly this reason. Restore it so the
        // document height tracks the full text and scrolling reaches the end.
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // Zero inset keeps glyph-bounding coordinates equal to text-view
        // coordinates, which `scroll(lineIndex:)` and `centerScoreTime()` rely on.
        textView.textContainerInset = NSSize.zero
        textView.autoresizingMask = [.width]
        textView.addSubview(wordBox)
        documentView = textView

        // Detect user scrolling by watching the clip view's origin move. This is
        // more reliable than `scrollWheel`/`willStartLiveScroll`, which the
        // `scrollWheel` override and missing inertia (mouse wheels) can suppress.
        // Our own programmatic scrolls are filtered out via `suppressScrollDetection`.
        contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.suppressScrollDetection else { return }
            self.delegate?.scrollWheelDidStartScroll()
        }
    }

    /// Mark the next short window of clip-view bounds changes as programmatic so
    /// the follow animation isn't mistaken for the user scrolling. Each call
    /// extends the window to cover the 0.3s follow animation plus slack.
    private func beginProgrammaticScroll() {
        suppressScrollDetection = true
        unsuppressWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.suppressScrollDetection = false }
        unsuppressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    func setupTextContents(
        lyrics: Lyrics?,
        converter: ChineseConverter?,
        restoreExplicit: ExplicitRenderRestoration? = nil
    ) {
        guard let lyrics = lyrics else {
            ranges = []
            textView.string = ""
            highlightedRange = nil
            hideWordBox()
            return
        }

        var lrcContent = ""
        var newRanges: [RenderedLineRange] = []
        let displayed: [(Int, LyricsLine)] = lyrics.lines.enumerated().compactMap { index, line in
            (line.enabled && !line.content.isEmpty) ? (index, line) : nil
        }
        let languageCode = lyrics.metadata.translationLanguages.first

        for (i, (originalIndex, line)) in displayed.enumerated() {
            let (mainContent, renderedTrans) = LineRenderer.render(
                line: line,
                lyricsLanguage: lyrics.metadata.language,
                translationLanguageCode: languageCode,
                convert: .all,
                converter: converter,
                restoreExplicit: restoreExplicit
            )
            var lineStr = mainContent
            if let trans = renderedTrans, displaySettings.preferBilingualLyrics {
                lineStr += "\n" + trans
            }
            let range = NSRange(location: lrcContent.utf16.count, length: lineStr.utf16.count)
            newRanges.append(RenderedLineRange(
                lineIndex: originalIndex,
                position: line.position,
                range: range,
                mainContentLength: mainContent.utf16.count,
                timetag: line.attachments.timetag
            ))
            lrcContent += lineStr
            if i < displayed.count - 1 {
                lrcContent += "\n\n"
            }
        }
        ranges = newRanges
        textView.string = lrcContent
        highlightedRange = nil
        hideWordBox()
        let range = textView.string.fullRange
        // `fontName` may be a name AppKit can't instantiate (e.g. the default
        // "SFProText-Regular"); fall back rather than force-unwrap, matching
        // `updateFont()` and the `lyricsWindowFont` helper.
        let font = NSFont(name: fontName, size: fontSize) ?? .labelFont(ofSize: fontSize)
        let style = NSMutableParagraphStyle().with {
            $0.alignment = .center
        }
        textView.textStorage?.addAttributes([
            .foregroundColor: textColor,
            .paragraphStyle: style,
            .font: font,
        ], range: range)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // Pin the text view to the visible width so the container wraps long
        // lines (autoresizing alone can't, since it starts from a zero frame).
        // This also gives the layout manager the right width to compute total
        // height, which fixes the vertical scroll range.
        textView.frame.size.width = contentSize.width
        updateFadeEdgeMask()
        updateEdgeInset()
    }

    // Don't treat the click that brings this floating panel forward (or a
    // click-through from another app) as an interaction — it only orders the
    // window front. Without this, an incidental click while you're working
    // elsewhere could commit a sync and rewrite the offset.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return false
    }

    override func mouseUp(with event: NSEvent) {
        // Sync mode commits on a single click; the HUD still needs a double-click
        // to seek. The earlier wild-offset bug came from the *activating* click and
        // from margin clicks committing — both now blocked by `acceptsFirstMouse`
        // being false and by the hit-test below only resolving clicks that land on
        // a glyph. Those are the safeguards that matter, so a deliberate single
        // click is safe without the awkward double-click.
        let requiredClicks = clickToSyncEnabled ? 1 : 2
        guard event.clickCount == requiredClicks,
              let position = lyricsPosition(atWindowPoint: event.locationInWindow) else {
            super.mouseUp(with: event)
            return
        }
        if clickToSyncEnabled {
            delegate?.syncToLyricsLine(at: position)
        } else {
            delegate?.doubleClickLyricsLine(at: position)
        }
    }

    /// The displayed line position the user clicked, or `nil` if there are no
    /// lyrics. Maps the window point through the text view's own point→character
    /// logic (`characterIndexForInsertion(at:)`), which accounts for
    /// `textContainerOrigin`. Comparing a view-space point against container-space
    /// glyph rects — as this used to — shifted every hit by a line and made
    /// clicks in the blank gaps between lines resolve to nothing.
    private func lyricsPosition(atWindowPoint windowPoint: NSPoint) -> TimeInterval? {
        guard let first = ranges.first,
              let last = ranges.last,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }
        let viewPoint = textView.convert(windowPoint, from: nil)
        let originY = textView.textContainerOrigin.y

        // Only accept clicks that land on the text block itself. The centering
        // insets leave tall empty margins above the first line and below the last;
        // a click there must not snap to — and re-sync — the nearest line.
        let textTop = layoutManager.boundingRect(forGlyphRange: first.range, in: textContainer).minY + originY
        let textBottom = layoutManager.boundingRect(forGlyphRange: last.range, in: textContainer).maxY + originY
        guard viewPoint.y >= textTop, viewPoint.y <= textBottom else { return nil }

        let charIndex = textView.characterIndexForInsertion(at: viewPoint)
        if let hit = ranges.first(where: { NSLocationInRange(charIndex, $0.range) }) {
            return wordPosition(in: hit, atCharacter: charIndex)
        }
        // The click fell in the gap between two lines; snap to the closest one.
        return ranges.min {
            characterDistance($0.range, to: charIndex) < characterDistance($1.range, to: charIndex)
        }?.position
    }

    /// The lyrics-file time of the word the click landed on: the start time of
    /// the timetag segment containing `charIndex`, offset from the line's own
    /// `position`. Falls back to the line start when the line carries no word
    /// timetags, so click-to-sync stays line-level for plain lyrics.
    private func wordPosition(in line: RenderedLineRange, atCharacter charIndex: Int) -> TimeInterval {
        guard let tags = line.timetag?.tags, !tags.isEmpty else { return line.position }
        let offset = charIndex - line.range.location
        // Tags are ascending by index; keep the latest one starting at or before
        // the clicked character — that's the word the click sits inside.
        var wordTime: TimeInterval = 0
        for tag in tags where tag.index <= offset {
            wordTime = tag.time
        }
        return line.position + wordTime
    }

    /// Distance from a character index to the nearest edge of `range`, in
    /// characters. Zero when the index is inside the range.
    private func characterDistance(_ range: NSRange, to index: Int) -> Int {
        if index < range.location { return range.location - index }
        let end = range.location + range.length
        if index > end { return index - end }
        return 0
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        // Any user scroll counts as browsing, so the strip holds the position you
        // scrolled to instead of being pulled back to the playing line. Check
        // `phase` (finger-down) as well as `momentumPhase` (inertia): the old
        // momentum-only check missed slow trackpad scrolls that carry no inertia.
        if event.phase.contains(.began) || event.phase.contains(.changed)
            || event.momentumPhase.contains(.began) {
            delegate?.scrollWheelDidStartScroll()
        } else if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
            delegate?.scrollWheelDidEndScroll()
        }
    }

    // overriding scrollwheel method breaks trackpad responsive scrolling ability
    override class var isCompatibleWithResponsiveScrolling: Bool {
        return true
    }

    private func updateFadeEdgeMask() {
        let location = fadeStripWidth / frame.height
        wantsLayer = true
        layer?.mask = CAGradientLayer().then {
            $0.frame = bounds
            $0.colors = [#colorLiteral(red: 0, green: 0, blue: 0, alpha: 0), #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1), #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1), #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0)] as [CGColor]
            $0.locations = [0, location as NSNumber, (1 - location) as NSNumber, 1]
            $0.startPoint = .zero
            $0.endPoint = CGPoint(x: 0, y: 1)
        }
    }

    private func updateEdgeInset() {
        guard let first = ranges.first,
              let last = ranges.last,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let bounding1 = layoutManager.boundingRect(forGlyphRange: first.range, in: textContainer)
        let topInset = frame.height / 2 - bounding1.height / 2
        let bounding2 = layoutManager.boundingRect(forGlyphRange: last.range, in: textContainer)
        let bottomInset = frame.height / 2 - bounding2.height / 2
        let newInsets = NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        automaticallyAdjustsContentInsets = false
        // Changing insets shifts the clip view too; mark it programmatic so it
        // isn't read as the user scrolling (which would drop following at open).
        if contentInsets.top != newInsets.top || contentInsets.bottom != newInsets.bottom {
            beginProgrammaticScroll()
        }
        contentInsets = newInsets
    }

    /// Find the displayed range nearest to the active original lyrics-line index.
    /// The clock can report indices for enabled lines we chose not to display
    /// (empty content); fall back to the closest displayed line so highlight/scroll
    /// stay anchored.
    private func displayedRange(forLineIndex lineIndex: Int) -> RenderedLineRange? {
        var left = 0
        var right = ranges.count - 1
        var found: RenderedLineRange?
        while left <= right {
            let mid = (left + right) / 2
            if ranges[mid].lineIndex <= lineIndex {
                found = ranges[mid]
                left = mid + 1
            } else {
                right = mid - 1
            }
        }
        return found ?? ranges.first
    }

    func highlight(lineIndex: Int?) {
        guard !ranges.isEmpty else { return }
        // Whole-line highlight is the non-karaoke path; no per-word box here.
        hideWordBox()
        let target: NSRange? = lineIndex.flatMap { displayedRange(forLineIndex: $0)?.range }

        if highlightedRange == target {
            return
        }

        highlightedRange.map { textView.textStorage?.addAttribute(.foregroundColor, value: textColor, range: $0) }
        if let target {
            textView.textStorage?.addAttribute(.foregroundColor, value: highlightColor, range: target)
        }

        highlightedRange = target
    }

    /// Karaoke variant of `highlight(lineIndex:)`: light up only the first
    /// `sungCharacters` UTF-16 units of the line's primary text in
    /// `highlightColor`, leaving the rest dimmed, so the line fills word-by-word
    /// as it's sung. `highlightedRange` still tracks the highlight-colored span
    /// (here, the sung prefix), so the `textColor`/`highlightColor` `didSet`
    /// re-theming keeps working without change. Clamped to `mainContentLength`
    /// so the fill never reaches an appended translation.
    func highlight(lineIndex: Int?, sungCharacters: Int) {
        guard !ranges.isEmpty,
              let lineIndex,
              let entry = displayedRange(forLineIndex: lineIndex) else { return }

        let sung = max(0, min(sungCharacters, entry.mainContentLength))
        let target: NSRange? = sung > 0 ? NSRange(location: entry.range.location, length: sung) : nil
        if highlightedRange == target { return }

        highlightedRange.map { textView.textStorage?.addAttribute(.foregroundColor, value: textColor, range: $0) }
        target.map { textView.textStorage?.addAttribute(.foregroundColor, value: highlightColor, range: $0) }
        highlightedRange = target
        if showsWordBox {
            positionWordBox(in: entry, sung: sung)
        }
    }

    /// Frame the `wordBox` around the word currently being sung — the timetag
    /// segment `[wordStart, wordEnd)` that contains the fill position `sung`.
    /// Skips reframing when the sung word hasn't changed (the fill ticks ~30Hz).
    private func positionWordBox(in entry: RenderedLineRange, sung: Int) {
        guard let tags = entry.timetag?.tags, !tags.isEmpty,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            hideWordBox()
            return
        }
        var wordStart = tags[0].index
        var wordEnd = entry.mainContentLength
        for i in tags.indices where tags[i].index <= sung {
            wordStart = tags[i].index
            wordEnd = (i + 1 < tags.count) ? tags[i + 1].index : entry.mainContentLength
        }
        let lo = entry.range.location + max(0, min(wordStart, entry.mainContentLength))
        var hi = entry.range.location + max(0, min(wordEnd, entry.mainContentLength))
        // The segment ends at the *next* word's start, so it trails the inter-word
        // space(s); trim them so the box hugs the word itself, not the gap after.
        let string = textView.string as NSString
        while hi > lo, let scalar = Unicode.Scalar(string.character(at: hi - 1)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            hi -= 1
        }
        let charRange = NSRange(location: lo, length: max(0, hi - lo))
        if wordBoxRange == charRange, !wordBox.isHidden { return }
        wordBoxRange = charRange

        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        let origin = textView.textContainerOrigin
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: origin.x, dy: origin.y)
            .insetBy(dx: -3, dy: -2)
        wordBox.frame = rect
        wordBox.isHidden = false
    }

    private func hideWordBox() {
        wordBox.isHidden = true
        wordBoxRange = nil
    }

    func scroll(lineIndex: Int?) {
        guard !ranges.isEmpty,
              let lineIndex,
              let entry = displayedRange(forLineIndex: lineIndex),
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let bounding = layoutManager.boundingRect(forGlyphRange: entry.range, in: textContainer)
        let point = NSPoint(x: 0, y: bounding.midY - frame.height / 2)
        // This is our scroll, not the user's — silence bounds-change detection for
        // the duration (including the caller's follow animation).
        beginProgrammaticScroll()
        textView.scroll(point)
    }

    func updateFont() {
        let range = textView.string.fullRange
        guard let font = NSFont(name: fontName, size: fontSize) else { return }
        textView.textStorage?.addAttribute(.font, value: font, range: range)
    }
}

/// Translucent strip marking the playback "now" line behind the synced lyric.
/// Click-through (its `hitTest` returns nil) so taps reach the scroll view
/// beneath it. Shared by the Sync by Ear panel and the lyrics HUD so both
/// surfaces frame the current line the same way.
final class LyricsNowBandView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
