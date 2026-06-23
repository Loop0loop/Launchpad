// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Launch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Launch", targets: ["Launch"]),
        .library(name: "LaunchApp", targets: ["LaunchApp"]),
        .library(name: "LaunchCore", targets: ["LaunchCore"])
    ],
    targets: [
        .target(name: "LaunchCore"),
        .target(name: "LaunchApp", dependencies: ["LaunchCore"]),
        .executableTarget(name: "Launch", dependencies: ["LaunchApp"]),
        .executableTarget(name: "LaunchCheck", dependencies: ["LaunchCore"])
    ]
)
