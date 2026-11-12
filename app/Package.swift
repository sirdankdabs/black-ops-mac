// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BlackOpsMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "BlackOpsMac", path: "Sources/BlackOpsMac")
    ]
)
