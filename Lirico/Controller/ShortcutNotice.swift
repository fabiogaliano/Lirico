import AppKit

/// A brief notice confirming what a global shortcut did. Shortcuts fire while another app is in
/// front, and some of what they change (the offset, Apple Music, the blocklist) shows nowhere else.
/// Placed at the top of the screen, clear of the desktop lyrics, which sit near the bottom by default.
@MainActor
final class ShortcutNotice {
    private static let visibleDuration: Duration = .seconds(1.5)
    private static let fadeDuration: TimeInterval = 0.2

    private let label = NSTextField(labelWithString: "")
    private lazy var panel = makePanel()
    private var hideTask: Task<Void, Never>?

    func show(_ message: String) {
        label.stringValue = message
        panel.setContentSize(panel.contentView?.fittingSize ?? .zero)
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: (visible.midX - panel.frame.width / 2).rounded(),
                y: visible.maxY - panel.frame.height - 12
            ))
        }
        panel.invalidateShadow()

        if !panel.isVisible {
            panel.alphaValue = reduceMotion ? 1 : 0
            panel.orderFrontRegardless()
        }
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                panel.animator().alphaValue = 1
            }
        }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )

        // Repeated presses (stepping the offset) extend the notice instead of flickering it.
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            await self?.hide()
        }
    }

    private func hide() async {
        if !reduceMotion {
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                panel.animator().alphaValue = 0
            }
            // A new notice during the fade-out takes the panel over.
            guard !Task.isCancelled else { return }
        }
        panel.orderOut(nil)
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        // A layer corner radius doesn't clip the behind-window blur; a mask image does.
        let radius: CGFloat = 12
        let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        background.maskImage = mask

        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -12),
        ])
        panel.contentView = background
        return panel
    }
}
