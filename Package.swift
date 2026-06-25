// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Launchpad",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Launchpad", targets: ["Launchpad"]),
        .executable(name: "LaunchpadPackager", targets: ["LaunchpadPackager"]),
        .executable(name: "LaunchpadCheck", targets: ["LaunchpadCheck"]),
        .library(name: "LaunchpadApp", targets: ["LaunchpadApp"]),
        .library(name: "LaunchpadCore", targets: ["LaunchpadCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .target(name: "LaunchpadCore", path: "Sources/LaunchCore"),
        .target(
            name: "LaunchpadApp",
            dependencies: [
                "LaunchpadCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/LaunchApp"
        ),
        .executableTarget(name: "Launchpad", dependencies: ["LaunchpadApp"], path: "Sources/Launch"),
        .executableTarget(name: "LaunchpadPackager", path: "Sources/LaunchPackager"),
        .executableTarget(name: "LaunchpadCheck", dependencies: ["LaunchpadCore"], path: "Sources/LaunchCheck"),
        .testTarget(name: "LaunchpadCoreTests", dependencies: ["LaunchpadCore"], path: "Tests/LaunchCoreTests")
    ]
)
