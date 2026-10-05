# Changelog

## 2.0.0

First release of Lirico, a fork of LyricsX 1.8.0.

- **breaking:** renamed LyricsX → Lirico
- **breaking:** require macOS 15
- removed the Sparkle updater (build from source with `make install-release`), Touch Bar lyrics, the manual player picker (Auto detects the active player across all apps) and the strict-search option
- search: results are ranked on how well title, artist, album and duration match, so decorated titles ("Remastered", "feat.") still match while reprises and intros don't; word-timed (karaoke) lyrics are preferred unless clearly worse, and source priority works
- search: results never land on a different track than the one playing, and local line-synced lyrics are replaced only by a word-timed or clearly better result, without overwriting the local file
- censored words in explicit lyrics (`f**k`) are restored at display time
- new Sync by Ear panel to fix a song's timing by ear, with karaoke word tuning
- block a song or album whose lyrics are wrong, and review or unblock them in Settings
- the menu shows what Lirico is doing for the current track
- settings rebuilt as native grouped panes; lyrics window, karaoke overlay and About window redesigned
- ⌘-drag to move the desktop lyrics; Lirico can launch and quit with any player in Auto
- launch at login uses macOS login items, with a hint when macOS holds the item for approval
- consistent naming across the app: Block, Desktop Lyrics, Sync by Ear, Save Lyrics to Apple Music
- global shortcuts for offset, Save to Apple Music and Block show a brief notice with the result
- changing the language offers Relaunch Now
- Search, Settings and Sync by Ear reopen where they were left; the lyrics window remembers Keep on top
- clearer search window: per-source errors, why Apply is unavailable, the loaded result is marked
- the lyrics window and Sync by Ear have their own text color; furigana and romaji settings sit with Desktop Lyrics
- VoiceOver labels throughout, and menu-bar scrolling and animations respect Reduce Motion
- translated into 16 languages
- saving lyrics and exporting to Apple Music no longer freeze the UI; plain-LRC export honors "Include translation"
- the desktop lyrics no longer cover the menu bar and Dock on a secondary display, and the lyrics-window toggle no longer steals focus
