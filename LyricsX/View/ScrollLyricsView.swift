import AppKit
import LyricsXFoundation

protocol ScrollLyricsViewDelegate: AnyObject {
    func doubleClickLyricsLine(at position: TimeInterval)
    func scrollWheelDidStartScroll()
    func scrollWheelDidEndScroll()
}

class ScrollLyricsView: NSScrollView {
    weak var delegate: ScrollLyricsViewDelegate?

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
    }

    private var ranges: [RenderedLineRange] = []
    private var highlightedRange: NSRange?

    func setupTextContents(lyrics: Lyrics?) {
        guard let lyrics = lyrics else {
            ranges = []
            textView.string = ""
            highlightedRange = nil
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
                convert: .all
            )
            var lineStr = mainContent
            if let trans = renderedTrans, displaySettings.preferBilingualLyrics {
                lineStr += "\n" + trans
            }
            let range = NSRange(location: lrcContent.utf16.count, length: lineStr.utf16.count)
            newRanges.append(RenderedLineRange(lineIndex: originalIndex, position: line.position, range: range))
            lrcContent += lineStr
            if i < displayed.count - 1 {
                lrcContent += "\n\n"
            }
        }
        ranges = newRanges
        textView.string = lrcContent
        highlightedRange = nil
        let range = textView.string.fullRange
        let font = NSFont(name: fontName, size: fontSize)!
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
        updateFadeEdgeMask()
        updateEdgeInset()
    }

    override func mouseUp(with event: NSEvent) {
        guard event.clickCount == 2 else {
            super.mouseUp(with: event)
            return
        }

        let clickPoint = textView.convert(event.locationInWindow, from: nil)
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let clicked = ranges.first { entry in
            let bounding = layoutManager.boundingRect(forGlyphRange: entry.range, in: textContainer)
            return bounding.contains(clickPoint)
        }
        if let clicked {
            delegate?.doubleClickLyricsLine(at: clicked.position)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        switch event.momentumPhase {
        case .began:
            delegate?.scrollWheelDidStartScroll()
        case .ended,
             .cancelled:
            delegate?.scrollWheelDidEndScroll()
        default:
            break
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
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
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

    func scroll(lineIndex: Int?) {
        guard !ranges.isEmpty,
              let lineIndex,
              let entry = displayedRange(forLineIndex: lineIndex),
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let bounding = layoutManager.boundingRect(forGlyphRange: entry.range, in: textContainer)
        let point = NSPoint(x: 0, y: bounding.midY - frame.height / 2)
        textView.scroll(point)
    }

    func updateFont() {
        let range = textView.string.fullRange
        guard let font = NSFont(name: fontName, size: fontSize) else { return }
        textView.textStorage?.addAttribute(.font, value: font, range: range)
    }
}
