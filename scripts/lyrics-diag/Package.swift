// swift-tools-version:6.2
import PackageDescription

// Standalone diagnostic that reuses the app's real evaluator + ranker
// (LiricoFoundation) and the same pinned LyricsKit providers the app builds
// against. Depending only on the local LiricoPackage keeps a single package
// graph, so candidate fetching and ranking cannot drift from the shipping app.
let package = Package(
    name: "lyrics-diag",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../LiricoPackage"),
    ],
    targets: [
        .executableTarget(
            name: "lyrics-diag",
            dependencies: [
                .product(name: "LiricoFoundation", package: "LiricoPackage"),
            ],
            // v5 mode: this throwaway tool crosses task boundaries with the
            // non-Sendable Lyrics class; we want warnings, not hard errors.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
