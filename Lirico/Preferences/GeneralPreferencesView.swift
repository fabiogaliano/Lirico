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
    @AppStorage(.menuBarLyricsEnabled) private var menuBarLyricsEnabled = false
    @AppStorage(.combinedMenubarLyrics) private var combinedMenubarLyrics = false
    @AppStorage(.hideMenuBarItems) private var hideMenuBarItems = false

    // Read from the system each time the pane appears: the user can also change it in
    // System Settings → General → Login Items.
    @State private var launchAtLogin = MainAppLoginItem.isEnabled
    @State private var loginItemApprovalPending = LoginItemApproval.isPending
    @State private var followsAllNowPlayingApps = defaults[.systemWideNowPlayingAppList].isEmpty

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
        // Approval happens in System Settings, so look again whenever the user comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginItemState()
        }
        .sheet(isPresented: $showingNowPlayingSheet, onDismiss: {
            followsAllNowPlayingApps = defaults[.systemWideNowPlayingAppList].isEmpty
        }) {
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
                    refreshLoginItemState()
                }
            ))
            // `PlayerLifecycle` follows the setting: it registers the helper and starts or stops it.
            Toggle("Open and quit with music player", isOn: $launchAndQuitWithPlayer)
                .onChange(of: launchAndQuitWithPlayer) { _, _ in refreshLoginItemState() }
            if loginItemApprovalPending {
                LabeledContent("Allow Lirico in System Settings › General › Login Items.") {
                    Button("Open Login Items…", action: LoginItemApproval.openSystemSettings)
                }
            }
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
                    HStack {
                        // An empty list doesn't limit anything.
                        if followsAllNowPlayingApps {
                            Text("All apps").foregroundStyle(.secondary)
                        }
                        Button("Choose…") { showingNowPlayingSheet = true }
                    }
                }
            }
        } header: {
            Text("Music Player")
        } footer: {
            if !useSystemWideNowPlaying {
                SettingsFooter("Follows whichever of Music, Spotify, Vox, Audirvana or Swinsian is playing.")
            } else if followsAllNowPlayingApps {
                SettingsFooter("Follows whatever macOS shows as Now Playing, from any app. Choose apps to limit it.")
            } else {
                SettingsFooter("Follows whatever macOS shows as Now Playing, limited to the apps you choose.")
            }
        }
    }

    private var menuBarSection: some View {
        Section {
            Toggle("Show lyrics in the menu bar", isOn: $menuBarLyricsEnabled)
            Toggle("Show icon and lyrics as one item", isOn: $combinedMenubarLyrics)
                .disabled(!menuBarLyricsEnabled)
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
        Section {
            Picker("Language", selection: $languagePickerIndex) {
                Text("System").tag(0)
                ForEach(Array(localizations.enumerated()), id: \.offset) { offset, lan in
                    Text(localizedLanguageName(for: lan)).tag(offset + 2)
                }
            }
            .onChange(of: languagePickerIndex) { _, idx in
                applyLanguageSelection(idx)
            }
            if languageSelectionPendingRelaunch {
                LabeledContent("Lirico needs to restart to use this language.") {
                    Button("Relaunch Now", action: AppRelauncher.relaunch)
                }
            }
        } header: {
            Text("Language")
        } footer: {
            if !languageSelectionPendingRelaunch {
                SettingsFooter("Takes effect after Lirico restarts.")
            }
        }
    }

    // MARK: - Helpers

    private func loadInitialState() {
        refreshLoginItemState()
        followsAllNowPlayingApps = defaults[.systemWideNowPlayingAppList].isEmpty
        if let lan = defaults[.selectedLanguage],
           let idx = localizations.firstIndex(of: lan) {
            languagePickerIndex = idx + 2
        } else {
            languagePickerIndex = 0
        }
    }

    private func refreshLoginItemState() {
        launchAtLogin = MainAppLoginItem.isEnabled
        loginItemApprovalPending = LoginItemApproval.isPending
    }

    private func applyLanguageSelection(_ index: Int) {
        if let lan = language(at: index) {
            defaults[.selectedLanguage] = lan
            defaults[.appleLanguages] = [lan]
        } else {
            defaults.remove(.selectedLanguage)
            defaults.remove(.appleLanguages)
        }
    }

    private func language(at index: Int) -> String? {
        index == 0 ? nil : localizations[index - 2]
    }

    private var languageSelectionPendingRelaunch: Bool {
        language(at: languagePickerIndex) != selectedLanguageAtLaunch
    }

    /// Each language in its own name, capitalized the way macOS lists them ("Español", not
    /// "español"): only the first letter, using that language's casing rules.
    private func localizedLanguageName(for lan: String) -> String {
        let locale = Locale(identifier: lan)
        let name: String
        if let idx = lan.firstIndex(of: "-") {
            let script = lan[idx...].dropFirst()
            name = locale.localizedString(forScriptCode: String(script)) ?? lan
        } else {
            name = locale.localizedString(forLanguageCode: lan) ?? lan
        }
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }
}

/// The language this run of Lirico is shown in. Read before this pane can change it: globals
/// initialize on first use, and the pane is the only place the setting is written.
private let selectedLanguageAtLaunch = defaults[.selectedLanguage]

// Filtered, sorted list of available localizations.
private let localizations = Bundle.main.localizations
    .filter { !$0.localizedCaseInsensitiveContains("Base") }
    .sorted()
