// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyShortcuts",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KeyShortcutsLib", type: .dynamic, targets: ["KeyShortcutsLib"])
    ],
    targets: [
        .target(
            name: "KeyShortcutsLib",
            path: "Sources/KeyShortcutsLib"
        ),
        .executableTarget(
            name: "KeyShortcuts",
            dependencies: ["KeyShortcutsLib"],
            path: "Sources/KeyShortcuts"
        )
    ]
)
