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

    @MainActor
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

// MARK: - General Preferences View

struct GeneralPreferencesView: View {
    @AppStorage(.launchAndQuitWithPlayer) private var launchAndQuitWithPlayer = false
    @AppStorage(.useSystemWideNowPlaying) private var useSystemWideNowPlaying = false
    @AppStorage(.combinedMenubarLyrics) private var combinedMenubarLyrics = false
    @AppStorage(.hideMenuBarItems) private var hideMenuBarItems = false

    // Read from the system each time the pane appears: the user can also change it in
    // System Settings → General → Login Items.
    @State private var launchAtLogin = MainAppLoginItem.isEnabled

    // Language picker — index 0 = system, 2+ = specific localization
    @State private var languagePickerIndex = 0

    @State private var showingNowPlayingSheet = false

    var body: some View {
        SettingsForm {
            startupSection
            musicPlayerSection
            menuBarSection
            languageSection
        }
        .onAppear(perform: loadInitialState)
        .sheet(isPresented: $showingNowPlayingSheet) {
            NowPlayingApplicationListRepresentable(onDismiss: { showingNowPlayingSheet = false })
                .frame(width: 600, height: 500)
        }
    }

    // MARK: - Sections

    private var startupSection: some View {
        Section {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in
                    MainAppLoginItem.setEnabled(enabled)
                    launchAtLogin = MainAppLoginItem.isEnabled
                }
            ))
            // `PlayerLifecycle` follows the setting: it registers the helper and starts or stops it.
            Toggle("Open and quit with music player", isOn: $launchAndQuitWithPlayer)
        } header: {
            Text("Startup")
        } footer: {
            SettingsFooter("Opens when a supported player starts, and quits after the last one closes.")
        }
    }

    private var musicPlayerSection: some View {
        Section {
            Picker("Follow", selection: $useSystemWideNowPlaying) {
                Text("Supported players").tag(false)
                Text("System Now Playing").tag(true)
            }
            if useSystemWideNowPlaying {
                LabeledContent("Apps") {
                    Button("Choose…") { showingNowPlayingSheet = true }
                }
            }
        } header: {
            Text("Music Player")
        } footer: {
            SettingsFooter(useSystemWideNowPlaying
                ? "Follows whatever macOS shows as Now Playing, limited to the apps you choose."
                : "Follows whichever of Music, Spotify, Vox, Audirvana or Swinsian is playing.")
        }
    }

    private var menuBarSection: some View {
        Section {
            Toggle("Show icon and lyrics as one item", isOn: $combinedMenubarLyrics)
            Toggle("Hide menu bar items", isOn: $hideMenuBarItems)
        } header: {
            Text("Menu Bar")
        } footer: {
            // With every status item gone there is no menu left to reach Settings from.
            if hideMenuBarItems {
                SettingsFooter("To open Settings again, open Lirico from Finder or Spotlight while it's running, or use the Show / Hide Settings shortcut.")
            }
        }
    }

    private var languageSection: some View {
        Section("Language") {
            Picker("Language", selection: $languagePickerIndex) {
                Text("System").tag(0)
                ForEach(Array(localizations.enumerated()), id: \.offset) { offset, lan in
                    Text(localizedLanguageName(for: lan)).tag(offset + 2)
                }
            }
            .onChange(of: languagePickerIndex) { _, idx in
                applyLanguageSelection(idx)
            }
        }
    }

    // MARK: - Helpers

    private func loadInitialState() {
        launchAtLogin = MainAppLoginItem.isEnabled
        if let lan = defaults[.selectedLanguage],
           let idx = localizations.firstIndex(of: lan) {
            languagePickerIndex = idx + 2
        } else {
            languagePickerIndex = 0
        }
    }

    private func applyLanguageSelection(_ index: Int) {
        if index == 0 {
            defaults.remove(.selectedLanguage)
            defaults.remove(.appleLanguages)
        } else {
            let lan = localizations[index - 2]
            defaults[.selectedLanguage] = lan
            defaults[.appleLanguages] = [lan]
        }
    }

    private func localizedLanguageName(for lan: String) -> String {
        if let idx = lan.firstIndex(of: "-") {
            let script = lan[idx...].dropFirst()
            return Locale(identifier: lan).localizedString(forScriptCode: String(script)) ?? lan
        }
        return Locale(identifier: lan).localizedString(forLanguageCode: lan) ?? lan
    }
}

// Filtered, sorted list of available localizations.
private let localizations = Bundle.main.localizations
    .filter { !$0.localizedCaseInsensitiveContains("Base") }
    .sorted()
