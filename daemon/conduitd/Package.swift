// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "conduitd",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "conduitd",
            path: "Sources/conduitd"
        )
    ]
)
