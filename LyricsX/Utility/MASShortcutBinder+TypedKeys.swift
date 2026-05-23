import AppKit
import GenericID
import MASShortcut

extension MASShortcutBinder {
    func bindShortcut<T>(_ key: UserDefaults.DefaultsKey<T>, to action: @escaping () -> Void) {
        bindShortcut(withDefaultsKey: key.key, toAction: action)
    }

    func bindBoolShortcut<T>(_ key: UserDefaults.DefaultsKey<T>, target: UserDefaults.DefaultsKey<Bool>) {
        bindShortcut(withDefaultsKey: key.key) {
            defaults[target] = !defaults[target]
        }
    }

    func bindShortcut<T>(_ key: UserDefaults.DefaultsKey<T>, on target: NSObject, to action: Selector) {
        bindShortcut(key) {
            _ = target.perform(action, with: self)
        }
    }
}

enum ShortcutBindings {
    static func install(actionTarget: AppDelegate, binder: MASShortcutBinder = MASShortcutBinder.shared()!) {
        binder.bindBoolShortcut(.shortcutToggleMenuBarLyrics, target: .menuBarLyricsEnabled)
        binder.bindBoolShortcut(.shortcutToggleKaraokeLyrics, target: .desktopLyricsEnabled)
        binder.bindShortcut(.shortcutShowLyricsWindow, on: actionTarget, to: #selector(AppDelegate.showLyricsHUD(_:)))
        binder.bindShortcut(.shortcutOffsetIncrease, on: actionTarget, to: #selector(AppDelegate.increaseOffset(_:)))
        binder.bindShortcut(.shortcutOffsetDecrease, on: actionTarget, to: #selector(AppDelegate.decreaseOffset(_:)))
        binder.bindShortcut(.shortcutWriteToiTunes, on: actionTarget, to: #selector(AppDelegate.writeToiTunes(_:)))
        binder.bindShortcut(.shortcutWrongLyrics, on: actionTarget, to: #selector(AppDelegate.wrongLyrics(_:)))
        binder.bindShortcut(.shortcutSearchLyrics, on: actionTarget, to: #selector(AppDelegate.searchLyrics(_:)))
        binder.bindShortcut(.shortcutTogglePreferences, on: actionTarget, to: #selector(AppDelegate.togglePreferences(_:)))
    }
}
