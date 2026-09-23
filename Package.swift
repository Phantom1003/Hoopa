// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hoopa",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Hoopa",
            path: "Sources/Hoopa",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
