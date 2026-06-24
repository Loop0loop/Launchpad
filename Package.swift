// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Launch",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Launch", targets: ["Launch"]),
        .executable(name: "LaunchPackager", targets: ["LaunchPackager"]),
        .library(name: "LaunchApp", targets: ["LaunchApp"]),
        .library(name: "LaunchCore", targets: ["LaunchCore"])
    ],
    targets: [
        .target(name: "LaunchCore"),
        .target(name: "LaunchApp", dependencies: ["LaunchCore"]),
        .executableTarget(name: "Launch", dependencies: ["LaunchApp"]),
        .executableTarget(name: "LaunchPackager"),
        .executableTarget(name: "LaunchCheck", dependencies: ["LaunchCore"])
    ]
)
