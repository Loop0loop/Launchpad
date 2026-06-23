import Foundation
import OSLog

enum LaunchLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Launch"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let input = Logger(subsystem: subsystem, category: "input")

    static func line(_ message: String) {
        FileHandle.standardError.write(Data("[Launch] \(message)\n".utf8))
    }
}
