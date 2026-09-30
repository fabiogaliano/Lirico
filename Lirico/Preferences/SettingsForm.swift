import AppKit
import SwiftUI

/// The grouped, System Settings–style form every settings pane is built on.
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form(content: content)
            .formStyle(.grouped)
            .toggleStyle(.switch)
    }
}

/// Secondary explanation shown under a section, like System Settings' footers.
struct SettingsFooter: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Editable list rows with the +/− bar macOS uses under lists, e.g. in Login Items.
struct EditableListControls: View {
    let addLabel: LocalizedStringKey
    let removeLabel: LocalizedStringKey
    let canRemove: Bool
    let add: () -> Void
    let remove: () -> Void
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: add) {
                Image(systemName: "plus").frame(width: 22, height: 18)
            }
            .accessibilityLabel(Text(addLabel))
            .help(Text(addLabel))
            Divider().frame(height: 14)
            Button(action: remove) {
                Image(systemName: "minus").frame(width: 22, height: 18)
            }
            .disabled(!canRemove)
            .accessibilityLabel(Text(removeLabel))
            .help(Text(removeLabel))
            Spacer()
            Button("Reset to Defaults", action: reset)
                .controlSize(.small)
        }
        .buttonStyle(.borderless)
    }
}
