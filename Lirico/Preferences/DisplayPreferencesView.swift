import AppKit
import SwiftUI

// MARK: - View Model

final class DisplayPreferencesViewModel: ObservableObject {
    @Published var desktopTextColor: Color = .white
    @Published var desktopProgressColor: Color = .accentColor
    @Published var desktopShadowColor: Color = Color(NSColor.black.withAlphaComponent(0.55))
    @Published var desktopBackgroundColor: Color = Color(NSColor.black.withAlphaComponent(0.85))
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

        let dtc: NSColor = defaults[.desktopLyricsColor] ?? nsWhite
        let dpc: NSColor = defaults[.desktopLyricsProgressColor] ?? nsAccent
        let dsc: NSColor = defaults[.desktopLyricsShadowColor] ?? nsShadow
        let dbc: NSColor = defaults[.desktopLyricsBackgroundColor] ?? nsBg
        let hhc: NSColor = defaults[.lyricsWindowHighlightColor] ?? nsAccent

        desktopTextColor = Color(dtc)
        desktopProgressColor = Color(dpc)
        desktopShadowColor = Color(dsc)
        desktopBackgroundColor = Color(dbc)
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
        "\(nsFont.displayName ?? nsFont.fontName) · \(Int(nsFont.pointSize)) pt"
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

    /// Saves only when the user picks a color. Saving from `onChange` also fired when `load()`
    /// replaced the placeholders, writing every registered default into the user's domain
    /// just by opening this pane, so later default changes never reached them.
    private func colorBinding(
        _ keyPath: ReferenceWritableKeyPath<DisplayPreferencesViewModel, Color>,
        save: @escaping (DisplayPreferencesViewModel) -> () -> Void
    ) -> Binding<Color> {
        Binding(
            get: { vm[keyPath: keyPath] },
            set: { newValue in
                vm[keyPath: keyPath] = newValue
                save(vm)()
            }
        )
    }

    var body: some View {
        SettingsForm {
            desktopLyricsSection
            desktopLyricsBehaviorSection
            lyricsWindowSection
        }
        .onAppear { vm.load() }
    }

    // MARK: - Sections

    private var desktopLyricsSection: some View {
        Section("Desktop Lyrics") {
            LabeledContent("Font") {
                FontPickerButton(font: vm.desktopFont) { old, new in
                    vm.desktopFontChanged(from: old, to: new)
                }
                .fixedSize()
            }
            if let fallback = vm.fontFallback {
                LabeledContent("Fallback font") {
                    HStack {
                        Text(fallback).foregroundStyle(.secondary)
                        Button("Remove") { vm.removeFontFallback() }
                    }
                }
            }
            ColorPicker("Text", selection: colorBinding(\.desktopTextColor, save: { $0.saveDesktopTextColor }), supportsOpacity: true)
            ColorPicker("Sung text", selection: colorBinding(\.desktopProgressColor, save: { $0.saveDesktopProgressColor }), supportsOpacity: true)
            ColorPicker("Shadow", selection: colorBinding(\.desktopShadowColor, save: { $0.saveDesktopShadowColor }), supportsOpacity: true)
            ColorPicker("Background", selection: colorBinding(\.desktopBackgroundColor, save: { $0.saveDesktopBackgroundColor }), supportsOpacity: true)
            Toggle("One line", isOn: $oneLineMode)
            Toggle("Vertical", isOn: $verticalMode)
        }
    }

    private var desktopLyricsBehaviorSection: some View {
        Section {
            Toggle("Drag with ⌘", isOn: $draggable)
            // Dragging needs the lyrics to stay under the pointer, so the overlay ignores this while draggable.
            Toggle("Hide when the mouse passes over", isOn: $hideWhenMousePassingBy)
                .disabled(draggable)
            Toggle("Hide when paused", isOn: $disableWhenPaused)
            Toggle("Hide in screenshots and recordings", isOn: $disableWhenScreenShot)
        } header: {
            Text("Desktop Lyrics Behavior")
        } footer: {
            if draggable {
                SettingsFooter("Hold ⌘ and drag the lyrics to move them. Hiding on mouse-over is off while dragging is on.")
            }
        }
    }

    private var lyricsWindowSection: some View {
        Section("Lyrics Window") {
            LabeledContent("Font") {
                FontPickerButton(font: vm.hudFont) { old, new in
                    vm.hudFontChanged(from: old, to: new)
                }
                .fixedSize()
            }
            ColorPicker("Highlight", selection: colorBinding(\.hudHighlightColor, save: { $0.saveHudHighlightColor }), supportsOpacity: true)
        }
    }
}
