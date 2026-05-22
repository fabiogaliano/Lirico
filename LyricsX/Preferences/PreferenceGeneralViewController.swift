import AppKit
import MusicPlayer
import ServiceManagement
import LaunchAtLogin

class PreferenceGeneralViewController: PreferenceViewController {
    @objc dynamic var launchAtLogin = LaunchAtLogin.kvo
    @IBOutlet var preferAuto: NSButton!
    @IBOutlet var preferiTunes: NSButton!
    @IBOutlet var preferSpotify: NSButton!
    @IBOutlet var preferVox: NSButton!
    @IBOutlet var preferAudirvana: NSButton!
    @IBOutlet var preferSwinsian: NSButton!

    @IBOutlet var autoLaunchButton: NSButton!

    @IBOutlet var savingPathPopUp: NSPopUpButton!
    @IBOutlet var userPathMenuItem: NSMenuItem!

    @IBOutlet var loadHomonymLrcButton: NSButton!

    @IBOutlet var languagePopUp: NSPopUpButton!

    private let persistenceSettings = PersistenceSettings()

    override func viewDidLoad() {
        super.viewDidLoad()

        let preferredPlayer = MusicPlayerName(index: defaults[.preferredPlayerIndex])
        switch preferredPlayer {
        case .appleMusic: preferiTunes.state = .on
        case .spotify: preferSpotify.state = .on
        case .vox: preferVox.state = .on
        case .audirvana: preferAudirvana.state = .on
        case .swinsian: preferSwinsian.state = .on
        case nil:
            preferAuto.state = .on
            autoLaunchButton.isEnabled = false
        }
        if let player = preferredPlayer, !player.supportsBesideTrackLyrics {
            loadHomonymLrcButton.isEnabled = false
        }

        if let url = persistenceSettings.customSavingDirectory {
            userPathMenuItem.title = url.lastPathComponent
            userPathMenuItem.toolTip = url.path
        } else {
            userPathMenuItem.isHidden = true
        }

        let localizedLan: [String] = localizations.map { lan in
            if let idx = lan.firstIndex(of: "-") {
                let script = lan[idx...].dropFirst()
                return Locale(identifier: lan).localizedString(forScriptCode: String(script))!
            } else {
                return Locale(identifier: lan).localizedString(forLanguageCode: lan)!
            }
        }
        languagePopUp.addItems(withTitles: localizedLan)

        if let lan = defaults[.selectedLanguage],
           let idx = localizations.firstIndex(of: lan) {
            languagePopUp.selectItem(at: idx + 2)
        }
    }

    @IBAction func toggleAutoLaunchAction(_ sender: NSButton) {
        let enabled = sender.state == .on
        if !SMLoginItemSetEnabled(lyricsXHelperIdentifier as CFString, enabled) {
            log("Failed to set login item enabled")
        }
    }

    @IBAction func showInFinderAction(_ sender: Any) {
        NSWorkspace.shared.open(persistenceSettings.storageDirectory().url)
    }

    @IBAction func chooseSavingPathAction(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.beginSheetModal(for: view.window!) { result in
            if result == .OK {
                let url = openPanel.url!
                self.persistenceSettings.customSavingDirectory = url
                self.userPathMenuItem.title = url.lastPathComponent
                self.userPathMenuItem.toolTip = url.path
                self.userPathMenuItem.isHidden = false
                self.savingPathPopUp.select(self.userPathMenuItem)
            } else {
                self.savingPathPopUp.selectItem(at: 0)
            }
        }
    }

    @IBAction func chooseLanguageAction(_ sender: NSPopUpButton) {
        let selectedIdx = sender.indexOfSelectedItem
        if selectedIdx == 0 {
            defaults.remove(.selectedLanguage)
            defaults.remove(.appleLanguages)
        } else {
            let lan = localizations[selectedIdx - 2]
            defaults[.selectedLanguage] = lan
            defaults[.appleLanguages] = [lan]
        }
    }

    @IBAction func helpTranslateAction(_ sender: NSButton) {
        NSWorkspace.shared.open(crowdinProjectURL)
    }

    @IBAction func preferredPlayerAction(_ sender: NSButton) {
        defaults[.preferredPlayerIndex] = sender.tag

        if sender.tag < 0 {
            autoLaunchButton.isEnabled = false
            autoLaunchButton.state = .off
            defaults[.launchAndQuitWithPlayer] = false
        } else {
            autoLaunchButton.isEnabled = true
        }

        if let player = MusicPlayerName(index: sender.tag), !player.supportsBesideTrackLyrics {
            loadHomonymLrcButton.isEnabled = false
            loadHomonymLrcButton.state = .off
            persistenceSettings.shouldLoadLyricsBesideTrack = false
        } else {
            loadHomonymLrcButton.isEnabled = true
        }
    }
}

private let localizations = Bundle.main.localizations.filter { !$0.localizedCaseInsensitiveContains("Base") }.sorted()
