import AppKit
import SwiftUI

// MARK: - About Window Controller

/// Hosts `AboutView` in a frosted, borderless-feeling window. Mirrors
/// `PreferenceWindowController` (SwiftUI via `NSHostingController`) but goes
/// full-bleed: a transparent titlebar over `.fullSizeContentView` lets the
/// `NSVisualEffectView` background run edge to edge, echoing the Sync by Ear
/// panel's translucency while still adapting to light/dark.
final class AboutWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        // The visual-effect view supplies the surface; an opaque window
        // background would draw a hard rectangle over its blur.
        window.backgroundColor = .clear
        window.isOpaque = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.setContentSize(NSSize(width: 380, height: 560))
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

// MARK: - About View

struct AboutView: View {
    @State private var showAcknowledgements = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                contributorsCard
                acknowledgementsCard
                footer
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(
            VisualEffectView(material: .underWindowBackground, blending: .behindWindow)
                .ignoresSafeArea()
        )
        .frame(width: 380, height: 560)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

            Text("Lirico")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.primary, .primary.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text(versionText)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.primary.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))

            Text("Synced lyrics for the music you're playing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(.top, 8)
    }

    // MARK: Contributors

    private var contributorsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(contributors.enumerated()), id: \.element.id) { index, person in
                if index > 0 {
                    Divider().opacity(0.4)
                }
                LinkRow(
                    role: person.role,
                    title: person.name,
                    subtitle: person.handle,
                    url: person.url
                )
            }
        }
        .cardSurface()
    }

    // MARK: Acknowledgements

    private var acknowledgementsCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { showAcknowledgements.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showAcknowledgements ? 90 : 0))
                    Text("Acknowledgements")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                    Spacer()
                    Text("\(components.count + libraries.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAcknowledgements {
                VStack(spacing: 0) {
                    ackGroup("Components", components)
                    ackGroup("Libraries", libraries)
                }
            }
        }
        .cardSurface()
    }

    /// A labelled run of credit rows inside the acknowledgements disclosure. The
    /// license sits in each row's subtitle so mixed-license groups stay legible.
    @ViewBuilder
    private func ackGroup(_ title: String, _ items: [Acknowledgement]) -> some View {
        Divider().opacity(0.4)
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 2)
        ForEach(items) { item in
            LinkRow(role: nil, title: item.name, subtitle: item.license, url: item.url)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 5) {
            Link(destination: licenseURL) {
                Text("Licensed under MPL-2.0")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Text("A fork of LyricsX")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 2)
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) · \(build)"
    }
}

// MARK: - Link Row

/// A tappable row that opens `url` in the browser, with a hover highlight and a
/// trailing "open in new" affordance. Used for both contributor and library
/// rows; `role` shows a small uppercase tag (e.g. MAINTAINER) when present.
private struct LinkRow: View {
    let role: String?
    let title: String
    let subtitle: String?
    let url: URL

    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if let role {
                        Text(role.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hovering ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.05) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Card Surface

/// Frosted, translucent card matching the Sync by Ear panel's "white at low
/// alpha" look, but expressed with `.primary` so it inverts correctly in light
/// mode. Clips children so per-row hover highlights stay inside the rounded edge.
private extension View {
    func cardSurface() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            )
    }
}

// MARK: - Visual Effect Background

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}

// MARK: - Credits Data

private let licenseURL = URL(string: "https://github.com/fabiogaliano/Lirico/blob/main/LICENSE")!

private struct Contributor: Identifiable {
    let id = UUID()
    let role: String
    let name: String
    let handle: String
    let url: URL
}

private struct Acknowledgement: Identifiable {
    let id = UUID()
    let name: String
    let license: String
    let url: URL
}

private let contributors: [Contributor] = [
    Contributor(
        role: "Maintainer",
        name: "Fábio Galiano",
        handle: "github.com/fabiogaliano/Lirico",
        url: URL(string: "https://github.com/fabiogaliano/Lirico")!
    ),
    Contributor(
        role: "Upstream",
        name: "Mx-Iris",
        handle: "github.com/MxIris-LyricsX-Project/LyricsX",
        url: URL(string: "https://github.com/MxIris-LyricsX-Project/LyricsX")!
    ),
    Contributor(
        role: "Origin",
        name: "Xander Deng",
        handle: "github.com/ddddxxx/LyricsX",
        url: URL(string: "https://github.com/ddddxxx/LyricsX")!
    ),
]

// Lirico's two core engines, both forked from the LyricsX project (MPL-2.0).
private let components: [Acknowledgement] = [
    Acknowledgement(name: "LyricsKit", license: "MPL-2.0", url: URL(string: "https://github.com/fabiogaliano/LyricsKit")!),
    Acknowledgement(name: "MusicPlayer", license: "MPL-2.0", url: URL(string: "https://github.com/MxIris-LyricsX-Project/MusicPlayer")!),
]

// Every library actually linked into the shipped app, with its real license as
// verified against each repo's LICENSE (GitHub SPDX detection). Note: CombineX
// and Then are vendored into Utility/ rather than resolved via SPM, so they no
// longer appear in Package.resolved — but their source ships, so they're
// credited here. Build-time-only macro/syntax packages are intentionally
// omitted. CryptoSwift is *not* MIT: its license adds a mandatory attribution
// clause, so it's flagged distinctly.
private let libraries: [Acknowledgement] = [
    Acknowledgement(name: "SwiftyOpenCC", license: "MIT", url: URL(string: "https://github.com/ddddxxx/SwiftyOpenCC")!),
    Acknowledgement(name: "GenericID", license: "MIT", url: URL(string: "https://github.com/MxIris-LyricsX-Project/GenericID")!),
    Acknowledgement(name: "SwiftCF", license: "MIT", url: URL(string: "https://github.com/MxIris-Library-Forks/SwiftCF")!),
    Acknowledgement(name: "Regex", license: "MIT", url: URL(string: "https://github.com/ddddxxx/Regex")!),
    Acknowledgement(name: "Semver", license: "MIT", url: URL(string: "https://github.com/ddddxxx/Semver")!),
    Acknowledgement(name: "TouchBarHelper", license: "MIT", url: URL(string: "https://github.com/ddddxxx/TouchBarHelper")!),
    Acknowledgement(name: "SnapKit", license: "MIT", url: URL(string: "https://github.com/SnapKit/SnapKit")!),
    Acknowledgement(name: "MarqueeLabel", license: "MIT", url: URL(string: "https://github.com/MxIris-LyricsX-Project/MarqueeLabel")!),
    Acknowledgement(name: "BigInt", license: "MIT", url: URL(string: "https://github.com/attaswift/BigInt")!),
    Acknowledgement(name: "LaunchAtLogin", license: "MIT", url: URL(string: "https://github.com/sindresorhus/LaunchAtLogin-Legacy")!),
    Acknowledgement(name: "UIFoundation", license: "MIT", url: URL(string: "https://github.com/Mx-Iris/UIFoundation")!),
    Acknowledgement(name: "FrameworkToolbox", license: "MIT", url: URL(string: "https://github.com/Mx-Iris/FrameworkToolbox")!),
    Acknowledgement(name: "CombineX", license: "MIT", url: URL(string: "https://github.com/cx-org/CombineX")!),
    Acknowledgement(name: "Then", license: "MIT", url: URL(string: "https://github.com/devxoul/Then")!),
    Acknowledgement(name: "Sparkle", license: "MIT", url: URL(string: "https://github.com/sparkle-project/Sparkle")!),
    Acknowledgement(name: "Swift Collections", license: "Apache-2.0", url: URL(string: "https://github.com/apple/swift-collections")!),
    Acknowledgement(name: "Swift Async Algorithms", license: "Apache-2.0", url: URL(string: "https://github.com/apple/swift-async-algorithms")!),
    Acknowledgement(name: "MASShortcut", license: "BSD-2-Clause", url: URL(string: "https://github.com/shpakovski/MASShortcut")!),
    Acknowledgement(
        name: "mediaremote-adapter",
        license: "BSD-3-Clause",
        url: URL(string: "https://github.com/MxIris-LyricsX-Project/mediaremote-adapter")!
    ),
    Acknowledgement(name: "CryptoSwift", license: "Custom · attribution", url: URL(string: "https://github.com/krzyzanowskim/CryptoSwift")!),
]
