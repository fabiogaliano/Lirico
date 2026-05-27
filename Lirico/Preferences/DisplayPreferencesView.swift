import AppKit
import SwiftUI

// MARK: - View Model

final class DisplayPreferencesViewModel: ObservableObject {
    @Published var desktopTextColor: Color = .white
    @Published var desktopProgressColor: Color = .accentColor
    @Published var desktopShadowColor: Color = Color(NSColor.black.withAlphaComponent(0.55))
    @Published var desktopBackgroundColor: Color = Color(NSColor.black.withAlphaComponent(0.85))
    @Published var hudTextColor: Color = Color(NSColor(calibratedWhite: 0.6, alpha: 1))
    @Published var hudHighlightColor: Color = .accentColor

    @Published var desktopFont: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    @Published var hudFont: NSFont = .labelFont(ofSize: NSFont.labelFontSize)

    @Published var fontFallback: String? = nil

    func load() {
        // Colors are stored as NSColor via keyed archive, so subscript returns NSColor?.
        // Defaults are registered in UserDefaultsRegistration so force-unwrap is safe
        // at runtime after app launch; the nil fallback guards against test/preview contexts.
        let nsWhite = NSColor.white
        let nsAccent = NSColor.controlAccentColor
        let nsShadow = NSColor.black.withAlphaComponent(0.55)
        let nsBg = NSColor.black.withAlphaComponent(0.85)
        let nsGray = NSColor(calibratedWhite: 0.6, alpha: 1)

        let dtc: NSColor = defaults[.desktopLyricsColor] ?? nsWhite
        let dpc: NSColor = defaults[.desktopLyricsProgressColor] ?? nsAccent
        let dsc: NSColor = defaults[.desktopLyricsShadowColor] ?? nsShadow
        let dbc: NSColor = defaults[.desktopLyricsBackgroundColor] ?? nsBg
        let htc: NSColor = defaults[.lyricsWindowTextColor] ?? nsGray
        let hhc: NSColor = defaults[.lyricsWindowHighlightColor] ?? nsAccent

        desktopTextColor = Color(dtc)
        desktopProgressColor = Color(dpc)
        desktopShadowColor = Color(dsc)
        desktopBackgroundColor = Color(dbc)
        hudTextColor = Color(htc)
        hudHighlightColor = Color(hhc)

        desktopFont = defaults.desktopLyricsFont
        hudFont = defaults.lyricsWindowFont

        fontFallback = defaults[.desktopLyricsFontNameFallback].first
    }

    func saveDesktopTextColor() {
        let c: NSColor = NSColor(desktopTextColor)
        defaults[.desktopLyricsColor] = c
    }

    func saveDesktopProgressColor() {
        let c: NSColor = NSColor(desktopProgressColor)
        defaults[.desktopLyricsProgressColor] = c
    }

    func saveDesktopShadowColor() {
        let c: NSColor = NSColor(desktopShadowColor)
        defaults[.desktopLyricsShadowColor] = c
    }

    func saveDesktopBackgroundColor() {
        let c: NSColor = NSColor(desktopBackgroundColor)
        defaults[.desktopLyricsBackgroundColor] = c
    }

    func saveHudTextColor() {
        let c: NSColor = NSColor(hudTextColor)
        defaults[.lyricsWindowTextColor] = c
    }

    func saveHudHighlightColor() {
        let c: NSColor = NSColor(hudHighlightColor)
        defaults[.lyricsWindowHighlightColor] = c
    }

    func desktopFontChanged(from oldFont: NSFont, to newFont: NSFont) {
        defaults[.desktopLyricsFontName] = newFont.fontName
        defaults[.desktopLyricsFontSize] = Int(newFont.pointSize)

        if (oldFont.familyName != nil && oldFont.familyName != newFont.familyName)
            || oldFont.fontName != newFont.fontName {
            var fallback = defaults[.desktopLyricsFontNameFallback]
            if let index = fallback.firstIndex(of: newFont.fontName) {
                fallback.remove(at: index)
            }
            fallback.insert(oldFont.fontName, at: 0)
            defaults[.desktopLyricsFontNameFallback] = Array(fallback.prefix(fontNameFallbackCountMax))
        }

        desktopFont = newFont
        fontFallback = defaults[.desktopLyricsFontNameFallback].first
    }

    func hudFontChanged(from oldFont: NSFont, to newFont: NSFont) {
        defaults[.lyricsWindowFontName] = newFont.fontName
        defaults[.lyricsWindowFontSize] = Int(newFont.pointSize)
        hudFont = newFont
    }

    func removeFontFallback() {
        defaults[.desktopLyricsFontNameFallback].removeAll()
        fontFallback = nil
    }
}

// MARK: - Font Picker Bridge

private final class FontPickerCoordinator: NSObject {
    var onFontChange: (NSFont, NSFont) -> Void
    var currentFont: NSFont

    init(currentFont: NSFont, onFontChange: @escaping (NSFont, NSFont) -> Void) {
        self.currentFont = currentFont
        self.onFontChange = onFontChange
    }

    @objc func showFontPanel(_ sender: NSButton) {
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(currentFont, isMultiple: false)
        let panel = manager.fontPanel(true)
        panel?.makeKeyAndOrderFront(sender)
    }

    @objc func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager else { return }
        let newFont = manager.convert(currentFont)
        onFontChange(currentFont, newFont)
        currentFont = newFont
    }

    @objc func validModesForFontPanel(_ fontPanel: NSFontPanel) -> UInt32 {
        return NSFontPanelSizeModeMask | NSFontPanelCollectionModeMask | NSFontPanelFaceModeMask
    }
}

private struct FontPickerButton: NSViewRepresentable {
    var font: NSFont
    var onFontChange: (NSFont, NSFont) -> Void

    func makeCoordinator() -> FontPickerCoordinator {
        FontPickerCoordinator(currentFont: font, onFontChange: onFontChange)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .rounded
        button.title = buttonTitle(for: font)
        button.target = context.coordinator
        button.action = #selector(FontPickerCoordinator.showFontPanel(_:))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.title = buttonTitle(for: font)
        context.coordinator.currentFont = font
        context.coordinator.onFontChange = onFontChange
    }

    private func buttonTitle(for nsFont: NSFont) -> String {
        "\(nsFont.fontName) - \(Int(nsFont.pointSize))"
    }
}

// MARK: - Display Preferences View

struct DisplayPreferencesView: View {
    @AppStorage("DesktopLyricsOneLineMode") private var oneLineMode = false
    @AppStorage("DesktopLyricsVerticalMode") private var verticalMode = false
    @AppStorage("DesktopLyricsDraggable") private var draggable = false
    @AppStorage("HideLyricsWhenMousePassingBy") private var hideWhenMousePassingBy = false
    @AppStorage("DisableLyricsWhenPaused") private var disableWhenPaused = false
    @AppStorage("DisableLyricsWhenSreenShot") private var disableWhenScreenShot = false

    @StateObject private var vm = DisplayPreferencesViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                desktopLyricsSection
                desktopLyricsBehaviorSection
                hudLyricsSection
            }
            .padding(20)
        }
        .onAppear { vm.load() }
    }

    // MARK: - Sections

    private var desktopLyricsSection: some View {
        SettingsSection(title: "Desktop Lyrics") {
            SettingsRow(label: "Font") {
                FontPickerButton(font: vm.desktopFont) { old, new in
                    vm.desktopFontChanged(from: old, to: new)
                }
            }
            if let fallback = vm.fontFallback {
                HStack {
                    Text(String(format: NSLocalizedString("Font Fallback: %@", comment: ""), fallback))
                        .foregroundColor(.secondary)
                    Button("Remove") { vm.removeFontFallback() }
                }
            }
            SettingsRow(label: "Text Color") {
                ColorPicker("", selection: $vm.desktopTextColor, supportsOpacity: true)
                    .labelsHidden()
                    .onChange(of: vm.desktopTextColor) { vm.saveDesktopTextColor() }
            }
            SettingsRow(label: "Karaoke Color") {
                ColorPicker("", selection: $vm.desktopProgressColor, supportsOpacity: true)
                    .labelsHidden()
                    .onChange(of: vm.desktopProgressColor) { vm.saveDesktopProgressColor() }
            }
            SettingsRow(label: "Shadow Color") {
                ColorPicker("", selection: $vm.desktopShadowColor, supportsOpacity: true)
                    .labelsHidden()
                    .onChange(of: vm.desktopShadowColor) { vm.saveDesktopShadowColor() }
            }
            SettingsRow(label: "Background Color") {
                ColorPicker("", selection: $vm.desktopBackgroundColor, supportsOpacity: true)
                    .labelsHidden()
                    .onChange(of: vm.desktopBackgroundColor) { vm.saveDesktopBackgroundColor() }
            }
            Toggle("One line mode", isOn: $oneLineMode)
            Toggle("Vertical mode", isOn: $verticalMode)
            Toggle("Draggable", isOn: $draggable)
        }
    }

    private var desktopLyricsBehaviorSection: some View {
        SettingsSection(title: "Desktop Lyrics Behavior") {
            Toggle("Hide when mouse passes by", isOn: $hideWhenMousePassingBy)
            Toggle("Disable when paused", isOn: $disableWhenPaused)
            Toggle("Disable during screenshot", isOn: $disableWhenScreenShot)
        }
    }

    private var hudLyricsSection: some View {
        SettingsSection(title: "HUD Lyrics Window") {
            SettingsRow(label: "Font") {
                FontPickerButton(font: vm.hudFont) { old, new in
                    vm.hudFontChanged(from: old, to: new)
                }
            }
            SettingsRow(label: "Text Color") {
                ColorPicker("", selection: $vm.hudTextColor, supportsOpacity: true)
                    .labelsHidden()
                    .onChange(of: vm.hudTextColor) { vm.saveHudTextColor() }
            }
            SettingsRow(label: "Highlight Color") {
                ColorPicker("", selection: $vm.hudHighlightColor, supportsOpacity: true)
                    .labelsHidden()
                    .onChange(of: vm.hudHighlightColor) { vm.saveHudHighlightColor() }
            }
        }
    }
}
