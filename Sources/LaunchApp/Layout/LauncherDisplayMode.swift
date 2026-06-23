import Foundation

enum LauncherDisplayMode: String, CaseIterable, Identifiable, Codable {
    case paged = "Paged"
    case vertical = "Vertical"

    var id: String {
        rawValue
    }
}
