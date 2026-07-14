import Foundation

enum BuildVariant: String {
    case development
    case production

    init?(argument: String) {
        switch argument.lowercased() {
        case "development", "dev", "debug": self = .development
        case "production", "prod", "release": self = .production
        default: return nil
        }
    }

    var swiftConfiguration: String { self == .production ? "release" : "debug" }
    var artifactName: String { self == .production ? "Launchpad" : "Launchpad-Dev" }
    var bundleIdentifier: String { self == .production ? "app.launchpad.mvp" : "app.launchpad.mvp.dev" }
    var bundleName: String { self == .production ? "Launchpad" : "Launchpad Dev" }
}

struct NotaryCredentials {
    let appleID: String
    let password: String
    let teamID: String
}

struct PackagerOptions {
    let command: String
    let variant: BuildVariant
    let signingIdentity: String?
    let notaryCredentials: NotaryCredentials?
    let notaryAppleID: String?
    let notaryPassword: String?
    let notaryTeamID: String?

    init(arguments: [String]) throws {
        command = arguments.first ?? "dmg"
        let dotEnv = DotEnv.load(
            from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")
        )

        var identity: String?
        var requestedVariant: String?
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--identity":
                identity = iterator.next()
            case "--variant":
                requestedVariant = iterator.next()
            default:
                break
            }
        }

        let productionOnly = command == "sign" || command == "notarize"
        if let value = requestedVariant ?? Self.configValue("LAUNCH_BUILD_VARIANT", dotEnv: dotEnv) {
            guard let parsed = BuildVariant(argument: value) else {
                throw PackagerError.invalidBuildVariant(value)
            }
            variant = parsed
        } else {
            variant = productionOnly ? .production : .development
        }
        if productionOnly, variant != .production {
            throw PackagerError.productionVariantRequired(command)
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
