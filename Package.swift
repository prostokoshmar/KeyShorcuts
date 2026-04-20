// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyShortcuts",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KeyShortcuts",
            path: "Sources/KeyShortcuts"
        )
    ]
)
