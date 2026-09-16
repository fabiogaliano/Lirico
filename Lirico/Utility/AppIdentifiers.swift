import Foundation

// The app and its helper are unsandboxed and ad-hoc signed, so they share
// preferences through an ordinary UserDefaults suite (a plist under
// ~/Library/Preferences) rather than a team-prefixed App Group — requesting an
// App Group would force an embedded provisioning profile, which on a free
// personal team expires weekly. Keep this in sync with LiricoHelper.
#if DEBUG
let lyricsXGroupIdentifier = "dev.fabiogaliano.Lirico.shared"
let lyricsXHelperIdentifier = "dev.fabiogaliano.LiricoHelper"
let lyricsXErrorDomain = "dev.fabiogaliano.Lirico"
#else
let lyricsXGroupIdentifier = "com.fabiogaliano.Lirico.shared"
let lyricsXHelperIdentifier = "com.fabiogaliano.LiricoHelper"
let lyricsXErrorDomain = "com.fabiogaliano.Lirico"
#endif
