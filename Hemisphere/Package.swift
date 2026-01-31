// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hemisphere",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Hemisphere",
            path: "Sources"
        )
    ]
)
