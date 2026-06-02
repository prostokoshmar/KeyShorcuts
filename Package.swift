// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyShortcuts",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KeyShortcutsLib", type: .dynamic, targets: ["KeyShortcutsLib"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "KeyShortcutsLib",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/KeyShortcutsLib"
        ),
        .executableTarget(
            name: "KeyShortcuts",
            dependencies: ["KeyShortcutsLib"],
            path: "Sources/KeyShortcuts"
        )
    ]
)
