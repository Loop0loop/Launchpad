import Foundation

enum PackagerError: Error, CustomStringConvertible {
    case missingFile(String)
    case commandFailed(String, Int32)
    case missingSigningIdentity
    case missingNotaryCredential(String)
    case invalidBuildVariant(String)
    case productionVariantRequired(String)
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
        case .invalidBuildVariant(let value):
            "Invalid build variant: \(value). Use development or production."
        case .productionVariantRequired(let command):
            "The \(command) command requires --variant production."
        case .unknownCommand(let command):
            "Unknown command: \(command)"
        }
    }
}
