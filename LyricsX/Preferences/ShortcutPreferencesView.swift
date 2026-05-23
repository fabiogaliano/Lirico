import AppKit
import MASShortcut
import SwiftUI

// MARK: - MASShortcutView bridge

private struct ShortcutRecorderView: NSViewRepresentable {
    let defaultsKey: String

    func makeNSView(context: Context) -> MASShortcutView {
        let view = MASShortcutView()
        view.associatedUserDefaultsKey = defaultsKey
        return view
    }

    func updateNSView(_ nsView: MASShortcutView, context: Context) {}
}

// MARK: - Shortcut Preferences View

struct ShortcutPreferencesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                lyricsDisplaySection
                lyricsTimingSection
                lyricsActionsSection
                appSection
            }
            .padding(20)
        }
    }

    // MARK: - Sections

    private var lyricsDisplaySection: some View {
        SettingsSection(title: "Lyrics Display") {
            shortcutRow("Show / Hide menu bar lyrics", key: "ShortcutToggleMenuBarLyrics")
            shortcutRow("Show / Hide karaoke lyrics", key: "ShortcutToggleKaraokeLyrics")
            shortcutRow("Show lyrics window", key: "ShortcutShowLyricsWindow")
        }
    }

    private var lyricsTimingSection: some View {
        SettingsSection(title: "Lyrics Timing") {
            shortcutRow("Increase lyrics offset", key: "ShortcutOffsetIncrease")
            shortcutRow("Decrease lyrics offset", key: "ShortcutOffsetDecrease")
        }
    }

    private var lyricsActionsSection: some View {
        SettingsSection(title: "Lyrics Actions") {
            shortcutRow("Write lyrics to Apple Music", key: "ShortcutWriteToiTunes")
            #if IS_FOR_MAS
            if defaults[.isInMASReview] != false {
                EmptyView()
            } else {
                shortcutRow("Search lyrics", key: "ShortcutSearchLyrics")
            }
            #else
            shortcutRow("Search lyrics", key: "ShortcutSearchLyrics")
            #endif
            shortcutRow("Mark as wrong lyrics", key: "ShortcutWrongLyrics")
        }
    }

    private var appSection: some View {
        SettingsSection(title: "App") {
            shortcutRow("Show / Hide preferences", key: "ShortcutTogglePreferences")
        }
    }

    // MARK: - Row builder

    private func shortcutRow(_ label: String, key: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            ShortcutRecorderView(defaultsKey: key)
                // MASShortcutViewStyleDefault intrinsic height is 19 px
                .frame(width: 160, height: 19)
        }
    }
}
