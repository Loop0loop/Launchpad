import Foundation

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
        try copy("public/Launch.png", to: resourcesURL.appendingPathComponent("Launch.png"))
        try copy("public/Launch_black.png", to: resourcesURL.appendingPathComponent("Launch_black.png"))
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
            "/usr/bin/plutil",
            ["-replace", plistKey, "-string", value, plist.path],
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
}
