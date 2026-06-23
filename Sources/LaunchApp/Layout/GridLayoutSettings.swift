import Foundation

struct GridLayoutSettings: Equatable, Hashable, Codable, Identifiable {
    let columns: Int
    let rows: Int

    var id: String {
        "\(columns)x\(rows)"
    }

    var label: String {
        id
    }

    var pageSize: Int {
        columns * rows
    }

    static let classic = GridLayoutSettings(columns: 7, rows: 5)
    static let presets = [
        classic,
        GridLayoutSettings(columns: 8, rows: 5),
        GridLayoutSettings(columns: 8, rows: 6)
    ]
}
