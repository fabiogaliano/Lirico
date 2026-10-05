// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

func envEnable(_ key: String, default defaultValue: Bool = false) -> Bool {
    guard let value = Context.environment[key] else {
        return defaultValue
    }
    if value == "1" {
        return true
    } else if value == "0" {
        return false
    } else {
        return defaultValue
    }
}

let useLocalDependency = envEnable("LIRICO_USE_LOCAL_DEPENDENCY")
let useLocalLiricoKit = envEnable("LIRICO_USE_LOCAL_LIRICOKIT", default: useLocalDependency)

extension Package.Dependency {
    enum LocalSearchPath {
        case package(path: String, isRelative: Bool, isEnabled: Bool)
    }

    /// An enabled local path that doesn't exist falls back to `remote` without notice: with no
    /// sibling `MusicPlayer` checkout, `LIRICO_USE_LOCAL_DEPENDENCY=1` switches only LiricoKit.
    static func package(local localSearchPaths: LocalSearchPath..., remote: Package.Dependency) -> Package.Dependency {
        for local in localSearchPaths {
            switch local {
            case .package(let path, let isRelative, let isEnabled):
                guard isEnabled else { continue }
                let url = if isRelative {
                    URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: #filePath))
                } else {
                    URL(fileURLWithPath: path)
                }

                if FileManager.default.fileExists(atPath: url.path) {
                    return .package(path: url.path)
                }
            }
        }
        return remote
    }
}

let package = Package(
    name: "LiricoPackage",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "LiricoFoundation",
            targets: ["LiricoFoundation"]
        ),
    ],
    dependencies: [
        .package(
            local: .package(
                path: "../../LiricoKit",
                isRelative: true,
                isEnabled: useLocalLiricoKit
            ),
            remote: .package(
                url: "https://github.com/fabiogaliano/LiricoKit",
                from: "3.0.0"
            )
        ),
        .package(
            local: .package(
                path: "../../MusicPlayer",
                isRelative: true,
                isEnabled: useLocalDependency
            ),
            remote: .package(
                url: "https://github.com/MxIris-LyricsX-Project/MusicPlayer",
                from: "1.8.0"
            )
        ),
    ],
    targets: [
        .target(
            name: "LiricoFoundation",
            dependencies: [
                .product(name: "LiricoKit", package: "LiricoKit"),
                .product(name: "MusicPlayer", package: "MusicPlayer"),
                .product(name: "LXMusicPlayer", package: "MusicPlayer"),
            ]
        ),
        .testTarget(
            name: "LiricoFoundationTests",
            dependencies: [
                "LiricoFoundation"
            ]
        ),
    ]
)

