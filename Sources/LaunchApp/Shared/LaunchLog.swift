import Foundation
import OSLog

enum LaunchLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Launch"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let input = Logger(subsystem: subsystem, category: "input")

    static func line(_ message: String) {
        let time = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        FileHandle.standardError.write(Data("[Launch \(ProcessInfo.processInfo.processIdentifier) t=\(time)] \(message)\n".utf8))
    }
}
