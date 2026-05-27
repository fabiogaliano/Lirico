import Cocoa
import SwiftCF
import CoreGraphicsExt
import CoreTextExt

class KaraokeLabel: NSTextField {
    @objc dynamic var isVertical = false {
        didSet {
            clearCache()
            invalidateIntrinsicContentSize()
        }
    }

    @objc dynamic var drawFurigana = false {
        didSet {
            clearCache()
            invalidateIntrinsicContentSize()
        }
    }

    @objc dynamic var drawRomajin = false {
        didSet {
            clearCache()
            invalidateIntrinsicContentSize()
        }
    }

    override var attributedStringValue: NSAttributedString {
        didSet {
            clearCache()
        }
    }

    override var stringValue: String {
        didSet {
            clearCache()
        }
    }

    @objc override dynamic var font: NSFont? {
        didSet {
            clearCache()
        }
    }

    @objc override dynamic var textColor: NSColor? {
        didSet {
            clearCache()
        }
    }

    @objc dynamic var progressColor: NSColor? {
        didSet {
            _progressAttrString = nil
            _progressCTFrame = nil
            needsDisplay = true
        }
    }

    private enum RenderVariant {
        case base
        case progress
    }

    private func clearCache() {
        _baseAttrString = nil
        _progressAttrString = nil
        _baseCTFrame = nil
        _progressCTFrame = nil
        needsLayout = true
        needsDisplay = true
        removeProgressAnimation()
    }

    private var _baseAttrString: NSAttributedString?
    private var _progressAttrString: NSAttributedString?
    private var romajinAnnotations: [(String, NSRange)] = []

    private func attrString(_ variant: RenderVariant) -> NSAttributedString {
        switch variant {
        case .base:
            if let attrString = _baseAttrString {
                return attrString
            }
            let attrString = buildAttributedString(foregroundColor: textColor)
            _baseAttrString = attrString
            return attrString
        case .progress:
            if let attrString = _progressAttrString {
                return attrString
            }
            let attrString = buildAttributedString(foregroundColor: progressColor ?? textColor)
            _progressAttrString = attrString
            return attrString
        }
    }

    private func buildAttributedString(foregroundColor: NSColor?) -> NSAttributedString {
        let attrString = NSMutableAttributedString(attributedString: attributedStringValue)
        let string = attrString.string as NSString
        let shouldDrawFurigana = drawFurigana && string.dominantLanguage == "ja"
        let shouldDrawRomajin = drawRomajin && string.dominantLanguage == "ja"
        let tokenizer = CFStringTokenizer.create(string: .from(string))
        romajinAnnotations = []
        for tokenType in IteratorSequence(tokenizer) where tokenType.contains(.isCJWordMask) {
            if isVertical {
                let tokenRange = tokenizer.currentTokenRange()
                let attr: [NSAttributedString.Key: Any] = [
                    .verticalGlyphForm: true,
                    .baselineOffset: (font?.pointSize ?? 24) * 0.25,
                ]
                attrString.addAttributes(attr, range: tokenRange.asNS)
            }
            guard shouldDrawFurigana else { continue }
            if let (furigana, range) = tokenizer.currentFuriganaAnnotation(in: string) {
                var attr: [CFAttributedString.Key: Any] = [.ctRubySizeFactor: 0.5]
                attr[.ctForegroundColor] = foregroundColor
                let annotation = CTRubyAnnotation.create(furigana, attributes: attr)
                attrString.addAttribute(.cf(.ctRubyAnnotation), value: annotation, range: range)
            }
            if shouldDrawRomajin, let (romajin, range) = tokenizer.currentRomanjiAnnotation(in: string) {
                romajinAnnotations.append((romajin as String, range))
            }
        }
        foregroundColor?.do { attrString.addAttributes([.foregroundColor: $0], range: attrString.fullRange) }
        return attrString
    }

    private var _baseCTFrame: CTFrame?
    private var _progressCTFrame: CTFrame?
//    private var ctFrame: CTFrame {
//        if let ctFrame = _ctFrame {
//            return ctFrame
//        }
//        layoutSubtreeIfNeeded()
//        let progression: CTFrameProgression = isVertical ? .rightToLeft : .topToBottom
//        let frameAttr: [CTFrame.AttributeKey: Any] = [.progression: progression.rawValue as NSNumber]
//        let framesetter = CTFramesetter.create(attributedString: attrString)
//        print(bounds.size)
//        let (suggestSize, fitRange) = framesetter.suggestFrameSize(constraints: bounds.size, frameAttributes: frameAttr)
//        let path = CGPath(rect: CGRect(origin: .zero, size: suggestSize), transform: nil)
//        let ctFrame = framesetter.frame(stringRange: fitRange, path: path, frameAttributes: frameAttr)
//        _ctFrame = ctFrame
//        return ctFrame
//    }

    private func ctFrame(_ variant: RenderVariant = .base, dirtyRect: NSRect? = nil) -> CTFrame {
        switch variant {
        case .base:
            if let ctFrame = _baseCTFrame {
                return ctFrame
            }
        case .progress:
            if let ctFrame = _progressCTFrame {
                return ctFrame
            }
        }

        if dirtyRect == nil {
            layoutSubtreeIfNeeded()
        }
        let progression: CTFrameProgression = isVertical ? .rightToLeft : .topToBottom
        let frameAttr: [CTFrame.AttributeKey: Any] = [.progression: progression.rawValue as NSNumber]
        let framesetter = CTFramesetter.create(attributedString: attrString(variant))
        let (suggestSize, fitRange) = framesetter.suggestFrameSize(constraints: (dirtyRect ?? bounds).size, frameAttributes: frameAttr)
        let path = CGPath(rect: CGRect(origin: .zero, size: suggestSize), transform: nil)
        let ctFrame = framesetter.frame(stringRange: fitRange, path: path, frameAttributes: frameAttr)
        switch variant {
        case .base:
            _baseCTFrame = ctFrame
        case .progress:
            _progressCTFrame = ctFrame
        }
        return ctFrame
    }

    override var intrinsicContentSize: NSSize {
        let progression: CTFrameProgression = isVertical ? .rightToLeft : .topToBottom
        let frameAttr: [CTFrame.AttributeKey: Any] = [.progression: progression.rawValue as NSNumber]
        let framesetter = CTFramesetter.create(attributedString: attrString(.base))
        let constraints = CGSize(width: CGFloat.infinity, height: .infinity)
        return framesetter.suggestFrameSize(constraints: constraints, frameAttributes: frameAttr).size
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        let cgContext = context.cgContext
        let baseFrame = ctFrame(.base, dirtyRect: dirtyRect)
        draw(frame: baseFrame, with: textColor, in: cgContext)

        guard let progressColor,
              let progressClipRect = currentProgressClipRect() else {
            return
        }

        cgContext.saveGState()
        cgContext.clip(to: progressClipRect)
        draw(frame: ctFrame(.progress, dirtyRect: dirtyRect), with: progressColor, in: cgContext)
        cgContext.restoreGState()
    }

    private func draw(frame: CTFrame, with color: NSColor?, in context: CGContext) {
        context.saveGState()
        configureTextRendering(in: context)
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1.0, y: -1.0)
        CTFrameDraw(frame, context)
        drawRomajiAnnotations(in: context, frame: frame, textColor: color)
        context.restoreGState()
    }

    // MARK: - Progress

    // TODO: multi-line
    private lazy var progressLayer: CALayer = {
        let pLayer = CALayer()
        wantsLayer = true
        pLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(pLayer)
        return pLayer
    }()

    private var progressLineBounds = CGRect.zero
    private var progressDisplayTimer: Timer?

    func setProgressAnimation(color: NSColor, progress: [(TimeInterval, Int)]) {
        removeProgressAnimation()
        progressColor = color
        guard let line = ctFrame().lines.first,
              let origin = ctFrame().lineOrigins(range: CFRange(location: 0, length: 1)).first else {
            return
        }
        var lineBounds = line.bounds()
        var transform = CGAffineTransform.translate(x: origin.x, y: origin.y)
        if isVertical {
            transform.transform(by: .swap() * .translate(y: -lineBounds.width))
            transform *= .flip(height: bounds.height)
        }
        lineBounds.apply(t: transform)
        progressLineBounds = lineBounds

        let scale = layer?.contentsScale ?? window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.anchorPoint = isVertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
        progressLayer.frame = lineBounds
        progressLayer.contentsScale = scale
        CATransaction.commit()

        guard let index = progress.firstIndex(where: { $0.0 > 0 }) else {
            needsDisplay = true
            return
        }
        var map = progress.map { ($0.0, line.offset(charIndex: $0.1).primary) }
        if index > 0 {
            let progress = map[index - 1].1 + CGFloat(map[index - 1].0) * (map[index].1 - map[index - 1].1) / CGFloat(map[index].0 - map[index - 1].0)
            map.replaceSubrange(..<index, with: [(0, progress)])
        }

        let duration = map.last!.0
        let animation = CAKeyframeAnimation()
        animation.keyTimes = map.map { ($0.0 / duration) as NSNumber }
        animation.values = map.map { $0.1 }
        animation.keyPath = isVertical ? "bounds.size.height" : "bounds.size.width"
        animation.duration = duration
        progressLayer.add(animation, forKey: "inlineProgress")
        startProgressDisplayTimer()
        needsDisplay = true
    }

    private func configureTextRendering(in context: CGContext) {
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(false)
        context.setShouldSmoothFonts(false)
        context.textMatrix = .identity
    }

    private func startProgressDisplayTimer() {
        progressDisplayTimer?.invalidate()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.needsDisplay = true
            if self.progressLayer.animation(forKey: "inlineProgress") == nil {
                timer.invalidate()
                if self.progressDisplayTimer === timer {
                    self.progressDisplayTimer = nil
                }
            }
        }
        progressDisplayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func currentProgressClipRect() -> CGRect? {
        guard !progressLineBounds.isEmpty else { return nil }
        let currentBounds = progressLayer.presentation()?.bounds ?? progressLayer.bounds
        let clipRect: CGRect
        if isVertical {
            let height = currentBounds.height.clamped(to: 0 ... progressLineBounds.height)
            clipRect = CGRect(
                x: progressLineBounds.minX,
                y: progressLineBounds.minY,
                width: progressLineBounds.width,
                height: height
            )
        } else {
            let width = currentBounds.width.clamped(to: 0 ... progressLineBounds.width)
            clipRect = CGRect(
                x: progressLineBounds.minX,
                y: progressLineBounds.minY,
                width: width,
                height: progressLineBounds.height
            )
        }
        return clipRect.isEmpty ? nil : clipRect
    }

    func pauseProgressAnimation() {
        let pausedTime = progressLayer.convertTime(CACurrentMediaTime(), from: nil)
        progressLayer.speed = 0
        progressLayer.timeOffset = pausedTime
    }

    func resumeProgressAnimation() {
        let pausedTime = progressLayer.timeOffset
        progressLayer.speed = 1
        progressLayer.timeOffset = 0
        progressLayer.beginTime = 0
        let timeSincePause = progressLayer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        progressLayer.beginTime = timeSincePause
        startProgressDisplayTimer()
    }

    func removeProgressAnimation() {
        progressDisplayTimer?.invalidate()
        progressDisplayTimer = nil
        progressLineBounds = .zero
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.speed = 1
        progressLayer.timeOffset = 0
        progressLayer.removeAnimation(forKey: "inlineProgress")
        progressLayer.frame = .zero
        CATransaction.commit()
        needsDisplay = true
    }

    private func drawRomajiAnnotations(in context: CGContext, frame: CTFrame, textColor: NSColor?) {
        guard drawRomajin, !romajinAnnotations.isEmpty else { return }

        let lines = frame.lines
        let origins = frame.lineOrigins(range: CFRangeMake(0, lines.count))
        var annotationIndex = 0
        let baseFontSize = font?.pointSize ?? 24

        for (line, origin) in zip(lines, origins) {
            for run in line.glyphRuns {
                let range = run.stringRange
                var subIndex = 0

                while annotationIndex + subIndex < romajinAnnotations.count {
                    let (romajin, annotationRange) = romajinAnnotations[annotationIndex + subIndex]
                    guard NSRange(location: range.location, length: range.length).contains(annotationRange.location) else {
                        break
                    }
                    var ascent: CGFloat = 0
                    var descent: CGFloat = 0
                    var leading: CGFloat = 0
                    let width = CTRunGetTypographicBounds(run, CFRangeMake(0, 0), &ascent, &descent, &leading)
                    var position = CGPoint.zero
                    CTRunGetPositions(run, CFRangeMake(0, 1), &position)
                    let glyphX = origin.x + position.x

                    let relativeOffset = CGFloat(annotationRange.location - range.location) / CGFloat(range.length) * width
                    let glyphBounds = CGRect(
                        x: glyphX + relativeOffset,
                        y: origin.y - descent,
                        width: width / CGFloat(range.length) * CGFloat(annotationRange.length),
                        height: ascent + descent
                    )
                    drawRubyAnnotation(romajin, in: glyphBounds, baseFontSize: baseFontSize, context: context, textColor: textColor)
                    subIndex += 1
                }
                annotationIndex += subIndex
            }
        }

        while annotationIndex < romajinAnnotations.count {
            let (romajin, _) = romajinAnnotations[annotationIndex]
            if let lastLine = lines.last, let lastOrigin = origins.last, let lastRun = lastLine.glyphRuns.last {
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                var leading: CGFloat = 0
                let width = CTRunGetTypographicBounds(lastRun, CFRangeMake(0, 0), &ascent, &descent, &leading)
                var position = CGPoint.zero
                CTRunGetPositions(lastRun, CFRangeMake(0, 1), &position)
                let glyphX = lastOrigin.x + position.x + width
                let glyphBounds = CGRect(
                    x: glyphX,
                    y: lastOrigin.y - descent,
                    width: width,
                    height: ascent + descent
                )
                drawRubyAnnotation(romajin, in: glyphBounds, baseFontSize: baseFontSize, context: context, textColor: textColor)
            }
            annotationIndex += 1
        }
    }

    private func drawRubyAnnotation(
        _ romajin: String,
        in glyphBounds: CGRect,
        baseFontSize: CGFloat,
        context: CGContext,
        textColor: NSColor?
    ) {
        var rubyFontSize = baseFontSize * 0.3
        var rubyAttr: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor ?? .black,
            .font: NSFont.systemFont(ofSize: rubyFontSize),
        ]
        var rubyString = NSAttributedString(string: romajin, attributes: rubyAttr)
        var rubyWidth = rubyString.size().width
        let maxWidth = glyphBounds.width

        while rubyWidth > maxWidth * 0.8, rubyFontSize > 1 {
            rubyFontSize *= 0.9
            rubyAttr[.font] = NSFont.systemFont(ofSize: rubyFontSize)
            rubyString = NSAttributedString(string: romajin, attributes: rubyAttr)
            rubyWidth = rubyString.size().width
        }

        let xOffset = (glyphBounds.width - rubyWidth) / 2
        context.textPosition = CGPoint(
            x: glyphBounds.minX + xOffset,
            y: glyphBounds.minY - baseFontSize * 0.2
        )
        CTLineDraw(CTLineCreateWithAttributedString(rubyString), context)
    }
}
