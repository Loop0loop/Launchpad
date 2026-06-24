import Foundation

enum PackagerError: Error, CustomStringConvertible {
    case missingFile(String)
    case commandFailed(String, Int32)
    case unknownCommand(String)

    var description: String {
        switch self {
        case .missingFile(let path):
            "Missing required file: \(path)"
        case .commandFailed(let command, let status):
            "Command failed (\(status)): \(command)"
        case .unknownCommand(let command):
            "Unknown command: \(command)"
        }
    }
}

struct LaunchPackager {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let name = "Launch"

    var buildDir: URL { root.appendingPathComponent(".build") }
    var appURL: URL { buildDir.appendingPathComponent("\(name).app") }
    var binaryURL: URL { root.appendingPathComponent(".build/apple/Products/Debug/Launch") }
    var stagingURL: URL { buildDir.appendingPathComponent("dmg") }
    var dmgURL: URL { buildDir.appendingPathComponent("\(name).dmg") }
    var backgroundURL: URL { root.appendingPathComponent("public/Launch.png") }

    func run(_ command: String) throws {
        switch command {
        case "app":
            try buildApp()
            print(relative(appURL))
        case "dmg":
            try buildDMG()
            print(relative(dmgURL))
        default:
            throw PackagerError.unknownCommand(command)
        }
    }

    func buildDMG() throws {
        try requireFile(backgroundURL)
        try buildApp()

        let fm = FileManager.default
        try removeIfExists(stagingURL)
        try removeIfExists(dmgURL)
        try fm.createDirectory(
            at: stagingURL.appendingPathComponent(".background"),
            withIntermediateDirectories: true
        )

        try fm.copyItem(at: appURL, to: stagingURL.appendingPathComponent("\(name).app"))
        try fm.createSymbolicLink(
            at: stagingURL.appendingPathComponent("Applications"),
            withDestinationURL: URL(fileURLWithPath: "/Applications")
        )
        try fm.copyItem(
            at: backgroundURL,
            to: stagingURL.appendingPathComponent(".background/Launch.png")
        )

        try runProcess(
            "/usr/bin/hdiutil",
            [
                "create",
                "-volname", name,
                "-srcfolder", stagingURL.path,
                "-ov",
                "-format", "UDZO",
                dmgURL.path
            ],
            quiet: true
        )
    }

    func buildApp() throws {
        try runProcess(
            "/usr/bin/xcrun",
            [
                "swift", "build",
                "--build-system", "xcode",
                "--disable-sandbox",
                "--cache-path", ".build/swiftpm-cache",
                "--config-path", ".build/swiftpm-config",
                "--security-path", ".build/swiftpm-security",
                "--product", name
            ],
            environment: [
                "DEVELOPER_DIR": environmentValue("DEVELOPER_DIR", default: "/Applications/Xcode.app/Contents/Developer"),
                "CLANG_MODULE_CACHE_PATH": environmentValue("CLANG_MODULE_CACHE_PATH", default: root.appendingPathComponent(".build/clang-module-cache").path)
            ]
        )

        try requireExecutable(binaryURL)
        try removeIfExists(appURL)

        let contentsURL = appURL.appendingPathComponent("Contents")
        let macOSURL = contentsURL.appendingPathComponent("MacOS")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        let fm = FileManager.default
        try fm.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        try copy("Resources/Info.plist", to: contentsURL.appendingPathComponent("Info.plist"))
        try copy("Resources/AppIcon.icns", to: resourcesURL.appendingPathComponent("AppIcon.icns"))
        try copy("Resources/MenuBarIcon.png", to: resourcesURL.appendingPathComponent("MenuBarIcon.png"))
        try copy("Resources/AppIconColor.png", to: resourcesURL.appendingPathComponent("AppIconColor.png"))
        try copy("Resources/AppIconMono.png", to: resourcesURL.appendingPathComponent("AppIconMono.png"))
        try fm.copyItem(at: binaryURL, to: macOSURL.appendingPathComponent(name))
        try fm.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: macOSURL.appendingPathComponent(name).path
        )
    }

    func copy(_ source: String, to destination: URL) throws {
        let sourceURL = root.appendingPathComponent(source)
        try requireFile(sourceURL)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
    }

    func requireFile(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PackagerError.missingFile(relative(url))
        }
    }

    func requireExecutable(_ url: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw PackagerError.missingFile(relative(url))
        }
    }

    func removeIfExists(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func runProcess(
        _ executable: String,
        _ arguments: [String],
        environment extraEnvironment: [String: String] = [:],
        quiet: Bool = false
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = root

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if !quiet, !output.isEmpty {
            print(output, terminator: output.hasSuffix("\n") ? "" : "\n")
        }
        guard process.terminationStatus == 0 else {
            if quiet, !output.isEmpty {
                print(output, terminator: output.hasSuffix("\n") ? "" : "\n")
            }
            throw PackagerError.commandFailed(([executable] + arguments).joined(separator: " "), process.terminationStatus)
        }
    }

    func environmentValue(_ key: String, default defaultValue: String) -> String {
        ProcessInfo.processInfo.environment[key] ?? defaultValue
    }

    func relative(_ url: URL) -> String {
        let path = url.path
        let rootPath = root.path + "/"
        guard path.hasPrefix(rootPath) else { return path }
        return String(path.dropFirst(rootPath.count))
    }
}

let command = CommandLine.arguments.dropFirst().first ?? "dmg"

do {
    try LaunchPackager().run(command)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
