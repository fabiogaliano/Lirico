import AppKit

extension NSUserInterfaceItemIdentifier {
    static let searchResultColumnTitle = NSUserInterfaceItemIdentifier("SearchResult.TableColumn.Title")
    static let searchResultColumnArtist = NSUserInterfaceItemIdentifier("SearchResult.TableColumn.Artist")
    static let searchResultColumnSource = NSUserInterfaceItemIdentifier("SearchResult.TableColumn.Source")
}

extension NSStoryboard.SceneIdentifier {
    static let desktopLyricsWindow = NSStoryboard.SceneIdentifier("DesktopLyricsWindow")
    static let lyricsHUDAccessory = NSStoryboard.SceneIdentifier("LyricsHUDAccessory")
}
