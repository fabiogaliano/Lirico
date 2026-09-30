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
            shortcutRow("Show / Hide menu bar lyrics", key: .shortcutToggleMenuBarLyrics)
            shortcutRow("Show / Hide karaoke lyrics", key: .shortcutToggleKaraokeLyrics)
            shortcutRow("Show lyrics window", key: .shortcutShowLyricsWindow)
        }
    }

    private var lyricsTimingSection: some View {
        SettingsSection(title: "Lyrics Timing") {
            shortcutRow("Increase lyrics offset", key: .shortcutOffsetIncrease)
            shortcutRow("Decrease lyrics offset", key: .shortcutOffsetDecrease)
        }
    }

    private var lyricsActionsSection: some View {
        SettingsSection(title: "Lyrics Actions") {
            shortcutRow("Write lyrics to Apple Music", key: .shortcutWriteToiTunes)
            #if IS_FOR_MAS
            if defaults[.isInMASReview] != false {
                EmptyView()
            } else {
                shortcutRow("Search lyrics", key: .shortcutSearchLyrics)
            }
            #else
            shortcutRow("Search lyrics", key: .shortcutSearchLyrics)
            #endif
            shortcutRow("Mark as wrong lyrics", key: .shortcutWrongLyrics)
        }
    }

    private var appSection: some View {
        SettingsSection(title: "App") {
            shortcutRow("Show / Hide preferences", key: .shortcutTogglePreferences)
        }
    }

    // MARK: - Row builder

    private func shortcutRow(_ label: LocalizedStringKey, key: UserDefaults.DefaultsKeys) -> some View {
        HStack {
            Text(label)
            Spacer()
            ShortcutRecorderView(defaultsKey: key.key)
                // MASShortcutViewStyleDefault intrinsic height is 19 px
                .frame(width: 160, height: 19)
                .accessibilityLabel(Text(label))
        }
    }
}
