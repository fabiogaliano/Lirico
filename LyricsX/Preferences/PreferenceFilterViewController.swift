import AppKit

class PreferenceFilterViewController: PreferenceViewController {
    @objc dynamic var directFilter = [LyricsFilterKeyword]()

    override func viewDidLoad() {
        super.viewDidLoad()

        loadFilter()
    }

    override func viewWillDisappear() {
        saveFilter()
    }

    func loadFilter() {
        directFilter = defaults[.lyricsFilterKeys].map {
            LyricsFilterKeyword(keyword: $0)
        }
    }

    func saveFilter() {
        defaults[.lyricsFilterKeys] = directFilter.map { $0.keyword }
    }

    @IBAction func resetFilterKey(_ sender: Any) {
        defaults.remove(.lyricsFilterKeys)
        loadFilter()
    }
}
