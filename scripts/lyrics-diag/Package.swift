// swift-tools-version:6.2
import PackageDescription

// Standalone diagnostic that reuses the app's real evaluator + ranker and
// LiricoKit providers through the local LiricoPackage, so candidate fetching
// and ranking logic cannot drift from the shipping app. Dependency versions
// resolve separately here, which is why the tool prints its LiricoKit version
// next to the app's pin.
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
