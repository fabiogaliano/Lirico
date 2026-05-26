// swift-tools-version:6.2
import PackageDescription

// Standalone diagnostic that reuses the app's real evaluator + ranker
// (LyricsXFoundation) and the same pinned LyricsKit providers the app builds
// against. Depending only on the local LyricsXPackage keeps a single package
// graph, so candidate fetching and ranking cannot drift from the shipping app.
let package = Package(
    name: "lyrics-diag",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../LyricsXPackage"),
    ],
    targets: [
        .executableTarget(
            name: "lyrics-diag",
            dependencies: [
                .product(name: "LyricsXFoundation", package: "LyricsXPackage"),
            ],
            // v5 mode: this throwaway tool crosses task boundaries with the
            // non-Sendable Lyrics class; we want warnings, not hard errors.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
