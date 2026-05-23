import AppKit
import SwiftUI

// MARK: - NowPlayingApplicationList sheet bridge

/// Wraps `NowPlayingApplicationListViewController` so it can be presented as
/// a SwiftUI sheet.
///
/// The `Coordinator` intercepts the VC's close button and calls the `onDismiss`
/// closure, which sets `showingNowPlayingSheet = false` directly rather than
/// relying on `presentingViewController`-based dismissal.
private struct NowPlayingApplicationListRepresentable: NSViewControllerRepresentable {
    let onDismiss: () -> Void

    final class Coordinator: NSObject {
        let onDismiss: () -> Void
        // Held weakly so the coordinator doesn't extend VC lifetime.
        weak var viewController: NowPlayingApplicationListViewController?

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        @objc func closeButtonTapped(_ sender: NSButton) {
            // Run the VC's own save logic before clearing the SwiftUI binding.
            if let vc = viewController {
                vc.closeButtonAction(sender)
            }
            onDismiss()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeNSViewController(context: Context) -> NowPlayingApplicationListViewController {
        let vc = NowPlayingApplicationListViewController()
        vc.preferredContentSize = NSSize(width: 600, height: 500)
        context.coordinator.viewController = vc
        // Retarget the close button so the coordinator drives dismissal via the
        // SwiftUI binding instead of dismiss(nil).
        vc.closeButton.target = context.coordinator
        vc.closeButton.action = #selector(Coordinator.closeButtonTapped(_:))
        return vc
    }

    func updateNSViewController(_ nsViewController: NowPlayingApplicationListViewController, context: Context) {}
}

// MARK: - Lab Preferences View

struct LabPreferencesView: View {
    // Touch Bar
    @AppStorage("TouchBarLyricsEnabled") private var touchBarLyricsEnabled = false

    // Now Playing
    @AppStorage("UseSystemWideNowPlaying") private var useSystemWideNowPlaying = false

    // Japanese
    @AppStorage("DesktopLyricsEnableFurigana") private var enableFurigana = false
    @AppStorage("DesktopLyricsEnableRomajin") private var enableRomaji = false

    // Apple Music export
    @AppStorage("WriteToiTunesAutomatically") private var writeAutomatically = false
    @AppStorage("WriteiTunesWithTranslation") private var writeWithTranslation = false
    @AppStorage("WriteiTunesConvertToPlainLRC") private var convertToPlainLRC = false

    // Musixmatch token is String? — @AppStorage doesn't support optionals, so
    // we mirror from UserDefaults manually and write back through SearchSettings.
    @State private var musixmatchToken: String = ""

    @State private var showingNowPlayingSheet = false

    private let searchSettings = SearchSettings()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                touchBarSection
                nowPlayingSection
                japaneseSection
                appleMusicSection
                musixmatchSection
            }
            .padding(20)
        }
        .onAppear {
            musixmatchToken = searchSettings.musixmatchToken ?? ""
        }
        .sheet(isPresented: $showingNowPlayingSheet) {
            NowPlayingApplicationListRepresentable(onDismiss: { showingNowPlayingSheet = false })
                .frame(width: 600, height: 500)
        }
    }

    // MARK: - Sections

    private var touchBarSection: some View {
        SettingsSection(title: "Touch Bar") {
            Toggle("Enable Touch Bar lyrics", isOn: $touchBarLyricsEnabled)
            Button("Customize Touch Bar…") {
                NSApplication.shared.toggleTouchBarCustomizationPalette(nil)
            }
            .disabled(!touchBarLyricsEnabled)
        }
    }

    private var nowPlayingSection: some View {
        SettingsSection(title: "Now Playing") {
            Toggle("Use system-wide Now Playing", isOn: $useSystemWideNowPlaying)
            Button("Customize Now Playing Applications…") {
                showingNowPlayingSheet = true
            }
            .disabled(!useSystemWideNowPlaying)
        }
    }

    private var japaneseSection: some View {
        SettingsSection(title: "Japanese") {
            Toggle("Enable Furigana", isOn: $enableFurigana)
            Toggle("Enable Romaji", isOn: $enableRomaji)
        }
    }

    private var appleMusicSection: some View {
        SettingsSection(title: "Apple Music Export") {
            Toggle("Write to Apple Music automatically", isOn: $writeAutomatically)
            Toggle("Include translation", isOn: $writeWithTranslation)
            Toggle("Convert to plain LRC", isOn: $convertToPlainLRC)
        }
    }

    private var musixmatchSection: some View {
        SettingsSection(title: "Musixmatch") {
            SettingsRow(label: "User token") {
                musixmatchTextField
            }
            // Explicit Apply button: reliable cross-version commit trigger.
            Button("Apply") { commitMusixmatchToken() }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder private var musixmatchTextField: some View {
        TextField("Token", text: $musixmatchToken)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 260)
            .onSubmit { commitMusixmatchToken() }
    }

    // MARK: - Helpers

    private func commitMusixmatchToken() {
        let trimmed = musixmatchToken.trimmingCharacters(in: .whitespacesAndNewlines)
        // Collapse empty string to nil so SearchSettings treats it as "no token".
        searchSettings.musixmatchToken = trimmed.isEmpty ? nil : trimmed
        musixmatchToken = trimmed
    }
}
