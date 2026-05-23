import AppKit
import LyricsXFoundation

class PreferenceLabViewController: PreferenceViewController {
    @IBOutlet var enableTouchBarLyricsButton: NSButton!

    @IBOutlet var musixmatchTokenField: NSTextField!

    private let searchSettings = SearchSettings()

    override func viewDidLoad() {
        super.viewDidLoad()

        enableTouchBarLyricsButton.bind(.value, withDefaultName: .touchBarLyricsEnabled)

        musixmatchTokenField.stringValue = searchSettings.musixmatchToken ?? ""
    }

    @IBAction func musixmatchTokenChanged(_ sender: NSTextField) {
        let value = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // `Key<String?>` treats nil as "remove" already; collapse empty-string
        // input into nil so we don't store a sentinel that breaks the `if let`
        // guard in `LyricsSearchPipeline.rebuildProviders`.
        searchSettings.musixmatchToken = value.isEmpty ? nil : value
        // `LyricsSearchPipeline` observes the token via SearchSettings and
        // rebuilds its provider list itself, so no direct call is needed here.
    }

    @IBAction func customizeAllowsNowPlayingApplicationsAction(_ sender: NSButton) {
        let viewController = NowPlayingApplicationListViewController()
        viewController.preferredContentSize = .init(width: 600, height: 500)
        presentAsSheet(viewController)
    }

    @IBAction func customizeTouchBarAction(_ sender: NSButton) {
        NSApplication.shared.toggleTouchBarCustomizationPalette(sender)
    }
}
