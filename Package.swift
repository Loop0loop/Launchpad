// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "Launchpad",
    platforms: [.macOS(.v27)],
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
            name: "LaunchAppPrivateSupport",
            path: "Sources/LaunchAppPrivateSupport",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .target(
            name: "LaunchpadApp",
            dependencies: [
                "LaunchpadCore",
                "LaunchAppPrivateSupport",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/LaunchApp"
        ),
        .executableTarget(name: "Launchpad", dependencies: ["LaunchpadApp"], path: "Sources/Launch"),
        .executableTarget(name: "LaunchpadPackager", path: "Sources/LaunchPackager"),
        .executableTarget(name: "LaunchpadCheck", dependencies: ["LaunchpadCore"], path: "Sources/LaunchCheck"),
        .testTarget(name: "LaunchpadCoreTests", dependencies: ["LaunchpadCore"], path: "Tests/LaunchCoreTests")
    ],
    swiftLanguageModes: [.v6]
)
