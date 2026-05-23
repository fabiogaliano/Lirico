import Combine
import Foundation
import GenericID

/// Typed view of the display-policy slice of `UserDefaults`.
///
/// Consumed by `LyricsDisplayCoordinator`, the menu-bar controller, the
/// desktop karaoke window, and the karaoke line presenter. The wrapper
/// isolates the policy surface from the flat `UserDefaults.DefaultsKeys`
/// namespace so the surfaces share one well-known place for display reads.
///
/// Cocoa Bindings (`bind(\.x, withDefaultName:)`) and KVO-based observers
/// (`observeDefaults`) intentionally still talk to `defaults` directly —
/// they need the key objects, and routing them through this struct would
/// duplicate the key list without removing the dependency.
struct DisplaySettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Pause behavior

    /// True when paused playback should hide the active lyric line.
    var disableLyricsWhenPaused: Bool {
        defaults[.disableLyricsWhenPaused]
    }

    /// Emits whenever `disableLyricsWhenPaused` is written to defaults.
    /// Erased to `AnyPublisher` so the coordinator's signature is independent
    /// of the underlying KVO-backed publisher type.
    func disableLyricsWhenPausedPublisher() -> AnyPublisher<Void, Never> {
        defaults.publisher(for: [.disableLyricsWhenPaused]).eraseToAnyPublisher()
    }

    // MARK: - Menu bar

    /// When true, the menu-bar icon and lyric item are both removed.
    var hideMenuBarItems: Bool {
        defaults[.hideMenuBarItems]
    }

    /// When true, the active lyric line is rendered in the menu bar.
    var menuBarLyricsEnabled: Bool {
        defaults[.menuBarLyricsEnabled]
    }

    /// When true, the icon and the lyric share a single status item;
    /// otherwise the lyric gets its own item next to the icon.
    var combinedMenubarLyrics: Bool {
        defaults[.combinedMenubarLyrics]
    }

    // MARK: - Desktop karaoke

    /// When true, the floating karaoke window renders the active line.
    var desktopLyricsEnabled: Bool {
        defaults[.desktopLyricsEnabled]
    }

    /// When true, the karaoke window shows only the primary line; otherwise
    /// it shows a translation or upcoming-line preview in the secondary row.
    var desktopLyricsOneLineMode: Bool {
        defaults[.desktopLyricsOneLineMode]
    }

    /// When true, the karaoke secondary row prefers a bilingual translation
    /// over the next-line preview. Also consulted by the HUD scroll view.
    var preferBilingualLyrics: Bool {
        defaults[.preferBilingualLyrics]
    }

    /// When true, the karaoke window accepts mouse drags to reposition.
    var desktopLyricsDraggable: Bool {
        defaults[.desktopLyricsDraggable]
    }

    /// When true, the karaoke view fades while the mouse hovers over it.
    /// Only applied when the window is also non-draggable.
    var hideLyricsWhenMousePassingBy: Bool {
        defaults[.hideLyricsWhenMousePassingBy]
    }

    /// Horizontal position of the karaoke window center, expressed as a
    /// 0…1 fraction of the screen width. Written back during a drag.
    var desktopLyricsXPositionFactor: CGFloat {
        get { defaults[.desktopLyricsXPositionFactor] }
        nonmutating set { defaults[.desktopLyricsXPositionFactor] = newValue }
    }

    /// Vertical position of the karaoke window center, expressed as a
    /// 0…1 fraction of the screen height. Written back during a drag.
    var desktopLyricsYPositionFactor: CGFloat {
        get { defaults[.desktopLyricsYPositionFactor] }
        nonmutating set { defaults[.desktopLyricsYPositionFactor] = newValue }
    }
}
