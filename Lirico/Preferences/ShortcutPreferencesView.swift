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
        SettingsForm {
            Section("Show / Hide") {
                shortcutRow("Menu bar lyrics", key: .shortcutToggleMenuBarLyrics)
                shortcutRow("Desktop lyrics", key: .shortcutToggleKaraokeLyrics)
                shortcutRow("Lyrics window", key: .shortcutShowLyricsWindow)
                shortcutRow("Settings", key: .shortcutTogglePreferences)
            }
            Section("Timing") {
                shortcutRow("Increase offset", key: .shortcutOffsetIncrease)
                shortcutRow("Decrease offset", key: .shortcutOffsetDecrease)
            }
            Section("Lyrics") {
                #if IS_FOR_MAS
                if defaults[.isInMASReview] == false {
                    shortcutRow("Search lyrics", key: .shortcutSearchLyrics)
                }
                #else
                shortcutRow("Search lyrics", key: .shortcutSearchLyrics)
                #endif
                shortcutRow("Mark as wrong lyrics", key: .shortcutWrongLyrics)
                shortcutRow("Save lyrics to Apple Music", key: .shortcutWriteToiTunes)
            }
        }
    }

    // MARK: - Row builder

    private func shortcutRow(_ label: LocalizedStringKey, key: UserDefaults.DefaultsKeys) -> some View {
        // Not LabeledContent: it aligns rows on the text baseline, which the AppKit recorder lacks.
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
