import AppKit
import SnapKit
import OSLog

class KaraokeLyricsView: NSView {
    private let backgroundView: NSView
    private let stackView: NSStackView

    @objc dynamic var isVertical = false {
        didSet {
            stackView.orientation = isVertical ? .horizontal : .vertical
            (isVertical ? displayLine2 : displayLine1).map { stackView.insertArrangedSubview($0, at: 0) }
            updateFontSize()
        }
    }

    @objc dynamic var drawFurigana = false
    @objc dynamic var drawRomajin = false

    @objc dynamic var font = NSFont.systemFont(ofSize: 22, weight: .semibold) { didSet { updateFontSize() } }
    @objc dynamic var textColor: NSColor = .white
    @objc dynamic var shadowColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.55)
    @objc dynamic var progressColor: NSColor = .controlAccentColor
    @objc dynamic var backgroundColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.85) {
        didSet {
            backgroundView.layer?.backgroundColor = backgroundColor.cgColor
        }
    }

    @objc dynamic var shouldHideWithMouse = true {
        didSet {
            mouseTest()
        }
    }

    var displayLine1: KaraokeLabel?
    var displayLine2: KaraokeLabel?

    override init(frame frameRect: NSRect) {
        self.stackView = NSStackView(frame: frameRect)
        stackView.orientation = .vertical
        stackView.autoresizingMask = [.width, .height]

        self.backgroundView = NSView()
        backgroundView.autoresizingMask = [.width, .height]
        backgroundView.wantsLayer = true
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(backgroundView)
        backgroundView.addSubview(stackView)
        backgroundView.layer?.cornerRadius = 12
        backgroundView.layer?.borderWidth = 0.5
        backgroundView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        // didSet doesn't fire for the init value, so without this the layer stays clear until the color changes.
        backgroundView.layer?.backgroundColor = backgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateFontSize() {
        var insetX = font.pointSize * 0.7
        var insetY = font.pointSize * 0.35
        if isVertical {
            (insetX, insetY) = (insetY, insetX)
        }
        stackView.snp.remakeConstraints {
            $0.edges.equalToSuperview().inset(NSEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX))
        }
        stackView.spacing = font.pointSize * 0.25
        backgroundView.layer?.cornerRadius = font.pointSize * 0.55
    }

    private func lyricsLabel(_ content: String) -> KaraokeLabel {
        if let view = stackView.subviews.lazy.compactMap({ $0 as? KaraokeLabel }).first(where: { !stackView.arrangedSubviews.contains($0) }) {
            view.alphaValue = 0
            view.stringValue = content
            view.removeProgressAnimation()
            view.removeFromSuperview()
            return view
        }
        return KaraokeLabel(labelWithString: content).then {
            $0.bind(\.font, to: self, withKeyPath: \.font)
            $0.bind(\.textColor, to: self, withKeyPath: \.textColor)
            $0.bind(\.progressColor, to: self, withKeyPath: \.progressColor)
            $0.bind(\._shadowColor, to: self, withKeyPath: \.shadowColor)
            $0.bind(\.isVertical, to: self, withKeyPath: \.isVertical)
            $0.bind(\.drawFurigana, to: self, withKeyPath: \.drawFurigana)
            $0.bind(\.drawRomajin, to: self, withKeyPath: \.drawRomajin)
            $0.alphaValue = 0
        }
    }

    func displayLrc(_ firstLine: String, secondLine: String = "") {
        var toBeHide = stackView.arrangedSubviews.compactMap { $0 as? KaraokeLabel }
        var toBeShow: [NSTextField] = []
        var shouldHideAll = false

        let index = isVertical ? 0 : 1
        if firstLine.trimmingCharacters(in: .whitespaces).isEmpty {
            displayLine1 = nil
            shouldHideAll = true
        } else if let current = displayLine1, let position = toBeHide.firstIndex(of: current), current.stringValue == firstLine {
            // Pause, resume and seek re-render the same line; swapping in a fresh label would blink it.
            toBeHide.remove(at: position)
        } else if toBeHide.count == 2, toBeHide[index].stringValue == firstLine {
            displayLine1 = toBeHide[index]
            toBeHide.remove(at: index)
        } else {
            let label = lyricsLabel(firstLine)
            displayLine1 = label
            toBeShow.append(label)
        }

        if !secondLine.trimmingCharacters(in: .whitespaces).isEmpty {
            if let current = displayLine2, let position = toBeHide.firstIndex(of: current), current.stringValue == secondLine {
                toBeHide.remove(at: position)
            } else {
                let label = lyricsLabel(secondLine)
                displayLine2 = label
                toBeShow.append(label)
            }
        } else {
            displayLine2 = nil
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
            context.allowsImplicitAnimation = true
            context.timingFunction = .swiftOut
            toBeHide.forEach {
                stackView.removeArrangedSubview($0)
                $0.isHidden = true
                $0.alphaValue = 0
                $0.removeProgressAnimation()
            }
            toBeShow.forEach {
                if isVertical {
                    stackView.insertArrangedSubview($0, at: 0)
                } else {
                    stackView.addArrangedSubview($0)
                }
                $0.isHidden = false
                $0.alphaValue = 1
            }
            isHidden = shouldHideAll
            layoutSubtreeIfNeeded()
        }, completionHandler: {
            MainActor.assumeIsolated { self.mouseTest() }
        })
    }

    // MARK: - Event

    var containsMouse: Bool {
        guard !isHiddenOrHasHiddenAncestor,
              let point = NSEvent.mouseLocation(in: self) else {
            return false
        }
        return bounds.contains(point)
    }

    func mouseTest() {
        let targetAlpha: CGFloat = shouldHideWithMouse && containsMouse ? 0 : 1
        if alphaValue != targetAlpha {
            animator().alphaValue = targetAlpha
        }
    }
}

extension NSEvent {
    @MainActor
    class func mouseLocation(in view: NSView) -> NSPoint? {
        guard let window = view.window else { return nil }
        let windowLocation = window.convertFromScreen(NSRect(origin: NSEvent.mouseLocation, size: .zero)).origin
        return view.convert(windowLocation, from: nil)
    }
}

extension NSTextField {
    // swiftlint:disable:next identifier_name
    @objc dynamic var _shadowColor: NSColor? {
        get {
            return shadow?.shadowColor
        }
        set {
            shadow = newValue.map { color in
                NSShadow().then {
                    $0.shadowBlurRadius = 8
                    $0.shadowColor = color
                    $0.shadowOffset = NSSize(width: 0, height: -1)
                }
            }
        }
    }
}
