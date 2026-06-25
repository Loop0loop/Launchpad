import Foundation

enum PackagerError: Error, CustomStringConvertible {
    case missingFile(String)
    case commandFailed(String, Int32)
    case missingSigningIdentity
    case missingNotaryCredential(String)
    case unknownCommand(String)

    var description: String {
        switch self {
        case .missingFile(let path):
            "Missing required file: \(path)"
        case .commandFailed(let command, let status):
            "Command failed (\(status)): \(command)"
        case .missingSigningIdentity:
            "Missing signing identity. Pass --identity \"Developer ID Application: ...\" or set LAUNCH_SIGN_IDENTITY."
        case .missingNotaryCredential(let key):
            "Missing notarization credential. Set \(key) in .env or the process environment."
        case .unknownCommand(let command):
            "Unknown command: \(command)"
        }
    }
}

enum DotEnv {
    static func load(from url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }

        var values: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else {
                continue
            }

            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst()
                value.removeLast()
            }
            values[key] = value
        }
        return values
    }
}

struct NotaryCredentials {
    let appleID: String
    let password: String
    let teamID: String
}

struct PackagerOptions {
    let command: String
    let signingIdentity: String?
    let notaryCredentials: NotaryCredentials?
    let notaryAppleID: String?
    let notaryPassword: String?
    let notaryTeamID: String?

    init(arguments: [String]) {
        command = arguments.first ?? "dmg"
        let dotEnv = DotEnv.load(
            from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")
        )

        var identity: String?
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            if argument == "--identity" {
                identity = iterator.next()
            }
        }
        signingIdentity = identity
            ?? Self.configValue("LAUNCH_SIGN_IDENTITY", dotEnv: dotEnv)
            ?? Self.discoverDeveloperIDApplicationIdentity()
        notaryAppleID = Self.configValue("APPLE_ID", dotEnv: dotEnv)
        notaryPassword = Self.configValue("APPLE_APP_SPECIFIC_PASSWORD", dotEnv: dotEnv)
        notaryTeamID = Self.configValue("APPLE_TEAM_ID", dotEnv: dotEnv)
        notaryCredentials = Self.notaryCredentials(
            appleID: notaryAppleID,
            password: notaryPassword,
            teamID: notaryTeamID
        )
    }

    static func configValue(_ key: String, dotEnv: [String: String]) -> String? {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }
        if let value = dotEnv[key], !value.isEmpty {
            return value
        }
        return nil
    }

    static func notaryCredentials(appleID: String?, password: String?, teamID: String?) -> NotaryCredentials? {
        guard let appleID, let password, let teamID else {
            return nil
        }
        return NotaryCredentials(appleID: appleID, password: password, teamID: teamID)
    }

    static func discoverDeveloperIDApplicationIdentity() -> String? {
        let home = ProcessInfo.processInfo.environment["HOME"].map(URL.init(fileURLWithPath:))
        let keychain = home?.appendingPathComponent("Library/Keychains/login.keychain-db").path
        let searches = [
            ["find-identity", "-v", "-p", "codesigning"],
            keychain.map { ["find-identity", "-v", "-p", "codesigning", $0] }
        ].compactMap { $0 }

        for arguments in searches {
            guard let output = runSecurity(arguments) else {
                continue
            }
            for line in output.split(whereSeparator: \.isNewline) {
                guard line.contains("\"Developer ID Application:"),
                      let firstQuote = line.firstIndex(of: "\""),
                      let lastQuote = line.lastIndex(of: "\""),
                      firstQuote != lastQuote else {
                    continue
                }
                return String(line[line.index(after: firstQuote)..<lastQuote])
            }
        }
        return nil
    }

    static func runSecurity(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else {
            return nil
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}

struct LaunchpadPackager {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let name = "Launchpad"

    var buildDir: URL { root.appendingPathComponent(".build") }
    var appURL: URL { buildDir.appendingPathComponent("\(name).app") }
    var buildConfiguration: String {
        let rawValue = ProcessInfo.processInfo.environment["LAUNCH_BUILD_CONFIGURATION"] ?? "debug"
        return rawValue.lowercased() == "release" ? "release" : "debug"
    }
    var xcodeBuildConfiguration: String {
        buildConfiguration == "release" ? "Release" : "Debug"
    }
    var binaryURL: URL { root.appendingPathComponent(".build/apple/Products/\(xcodeBuildConfiguration)/Launchpad") }
    var packageFrameworksURL: URL { root.appendingPathComponent(".build/apple/Products/\(xcodeBuildConfiguration)/Frameworks") }
    var stagingURL: URL { buildDir.appendingPathComponent("dmg") }
    var dmgURL: URL { buildDir.appendingPathComponent("\(name).dmg") }
    var backgroundURL: URL { root.appendingPathComponent("public/Launch.png") }

    func run(_ options: PackagerOptions) throws {
        switch options.command {
        case "app":
            try buildApp()
            print(relative(appURL))
        case "dmg":
            try buildDMG()
            print(relative(dmgURL))
        case "sign":
            guard let identity = options.signingIdentity, !identity.isEmpty else {
                throw PackagerError.missingSigningIdentity
            }
            try buildSignedDMG(identity: identity)
            print(relative(dmgURL))
        case "notarize":
            guard let identity = options.signingIdentity, !identity.isEmpty else {
                throw PackagerError.missingSigningIdentity
            }
            guard let credentials = options.notaryCredentials else {
                try requireNotaryCredential("APPLE_ID", from: options)
                try requireNotaryCredential("APPLE_APP_SPECIFIC_PASSWORD", from: options)
                try requireNotaryCredential("APPLE_TEAM_ID", from: options)
                throw PackagerError.missingNotaryCredential("APPLE_ID")
            }
            try notarize(identity: identity, credentials: credentials)
            print(relative(dmgURL))
        default:
            throw PackagerError.unknownCommand(options.command)
        }
    }

    func buildSignedDMG(identity: String) throws {
        try buildDMG(signingIdentity: identity)
    }

    func notarize(identity: String, credentials: NotaryCredentials) throws {
        try buildSignedDMG(identity: identity)
        let notaryOutput = try runProcess(
            "/usr/bin/xcrun",
            [
                "notarytool", "submit", dmgURL.path,
                "--apple-id", credentials.appleID,
                "--password", credentials.password,
                "--team-id", credentials.teamID,
                "--wait"
            ],
            redactedCommand: "/usr/bin/xcrun notarytool submit \(relative(dmgURL)) --apple-id <redacted> --password <redacted> --team-id <redacted> --wait"
        )
        if notaryOutput.contains("status: Invalid") {
            if let submissionID = notarySubmissionID(from: notaryOutput) {
                _ = try? runProcess(
                    "/usr/bin/xcrun",
                    [
                        "notarytool", "log", submissionID,
                        "--apple-id", credentials.appleID,
                        "--password", credentials.password,
                        "--team-id", credentials.teamID
                    ],
                    redactedCommand: "/usr/bin/xcrun notarytool log \(submissionID) --apple-id <redacted> --password <redacted> --team-id <redacted>"
                )
            }
            throw PackagerError.commandFailed("notarytool submit returned Invalid", 1)
        }
        try runProcess("/usr/bin/xcrun", ["stapler", "staple", dmgURL.path])
        try runProcess("/usr/bin/xcrun", ["stapler", "validate", dmgURL.path])
    }

    func buildDMG(signingIdentity: String? = nil) throws {
        try requireFile(backgroundURL)
        try buildApp()
        if let signingIdentity {
            try signApp(identity: signingIdentity)
        }

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

        if let signingIdentity {
            try signDMG(identity: signingIdentity)
        }
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
                "-c", buildConfiguration,
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

        try copyInfoPlist(to: contentsURL.appendingPathComponent("Info.plist"))
        try copy("Resources/AppIcon.icns", to: resourcesURL.appendingPathComponent("AppIcon.icns"))
        try copy("Resources/MenuBarIcon.png", to: resourcesURL.appendingPathComponent("MenuBarIcon.png"))
        try copy("Resources/AppIconColor.png", to: resourcesURL.appendingPathComponent("AppIconColor.png"))
        try copy("Resources/AppIconMono.png", to: resourcesURL.appendingPathComponent("AppIconMono.png"))
        try fm.copyItem(at: binaryURL, to: macOSURL.appendingPathComponent(name))
        try copyPackageFrameworks(to: contentsURL.appendingPathComponent("Frameworks"))
        try addFrameworksRPath(to: macOSURL.appendingPathComponent(name))
        try fm.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: macOSURL.appendingPathComponent(name).path
        )
    }

    func signApp(identity: String) throws {
        try requireFile(appURL)
        var arguments = [
            "--force",
            "--deep",
            "--options", "runtime",
            "--sign", identity
        ]
        if identity != "-" {
            arguments.append("--timestamp")
        }
        arguments.append(appURL.path)
        try runProcess("/usr/bin/codesign", arguments)
        try runProcess(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", "--verbose=4", appURL.path]
        )
    }

    func signDMG(identity: String) throws {
        try requireFile(dmgURL)
        var arguments = [
            "--force",
            "--sign", identity
        ]
        if identity != "-" {
            arguments.append("--timestamp")
        }
        arguments.append(dmgURL.path)
        try runProcess("/usr/bin/codesign", arguments)
        try runProcess(
            "/usr/bin/codesign",
            ["--verify", "--verbose=4", dmgURL.path]
        )
    }

    func copy(_ source: String, to destination: URL) throws {
        let sourceURL = root.appendingPathComponent(source)
        try requireFile(sourceURL)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
    }

    func copyInfoPlist(to destination: URL) throws {
        try copy("Resources/Info.plist", to: destination)
        injectInfoValue("SPARKLE_FEED_URL", plistKey: "SUFeedURL", into: destination)
        injectInfoValue("SPARKLE_PUBLIC_ED_KEY", plistKey: "SUPublicEDKey", into: destination)
    }

    func injectInfoValue(_ envKey: String, plistKey: String, into plist: URL) {
        let dotEnv = DotEnv.load(from: root.appendingPathComponent(".env"))
        guard let value = PackagerOptions.configValue(envKey, dotEnv: dotEnv), !value.isEmpty else { return }
        _ = try? runProcess(
            "/usr/libexec/PlistBuddy",
            ["-c", "Set :\(plistKey) \(value)", plist.path],
            quiet: true
        )
    }

    func copyPackageFrameworks(to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: packageFrameworksURL.path) else { return }
        try FileManager.default.copyItem(at: packageFrameworksURL, to: destination)
    }

    func addFrameworksRPath(to binary: URL) throws {
        _ = try? runProcess(
            "/usr/bin/install_name_tool",
            ["-delete_rpath", "@executable_path/../lib", binary.path],
            quiet: true
        )
        try runProcess(
            "/usr/bin/install_name_tool",
            ["-add_rpath", "@executable_path/../Frameworks", binary.path],
            quiet: true
        )
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

    @discardableResult
    func runProcess(
        _ executable: String,
        _ arguments: [String],
        environment extraEnvironment: [String: String] = [:],
        quiet: Bool = false,
        redactedCommand: String? = nil
    ) throws -> String {
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
            let command = redactedCommand ?? ([executable] + arguments).joined(separator: " ")
            throw PackagerError.commandFailed(command, process.terminationStatus)
        }
        return output
    }

    func notarySubmissionID(from output: String) -> String? {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        for (index, line) in lines.enumerated() where line.trimmingCharacters(in: .whitespaces) == "id:" {
            guard index + 1 < lines.count else { continue }
            return lines[index + 1].trimmingCharacters(in: .whitespaces)
        }
        for line in lines where line.trimmingCharacters(in: .whitespaces).hasPrefix("id:") {
            return line.replacingOccurrences(of: "id:", with: "").trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    func requireNotaryCredential(_ key: String, from options: PackagerOptions) throws {
        let hasCredential: Bool
        switch key {
        case "APPLE_ID":
            hasCredential = options.notaryAppleID?.isEmpty == false
        case "APPLE_APP_SPECIFIC_PASSWORD":
            hasCredential = options.notaryPassword?.isEmpty == false
        case "APPLE_TEAM_ID":
            hasCredential = options.notaryTeamID?.isEmpty == false
        default:
            hasCredential = false
        }
        if !hasCredential {
            throw PackagerError.missingNotaryCredential(key)
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

let options = PackagerOptions(arguments: Array(CommandLine.arguments.dropFirst()))

do {
    try LaunchpadPackager().run(options)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
