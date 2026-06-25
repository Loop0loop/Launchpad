public enum LayoutOrder {
    public static func apply(_ order: [String], to apps: [LaunchApp]) -> [LaunchApp] {
        let byID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        let ordered = order.compactMap { byID[$0] }
        let orderedIDs = Set(ordered.map(\.id))
        return ordered + apps.filter { !orderedIDs.contains($0.id) }
    }

    public static func move(_ id: String, before targetID: String, in order: [String]) -> [String] {
        guard id != targetID, order.contains(id), let target = order.firstIndex(of: targetID) else {
            return order
        }

        var next = order.filter { $0 != id }
        next.insert(id, at: min(target, next.count))
        return next
    }

    /// Move `id` to an absolute slot. Shared by the live drag preview and the committed
    /// drop so what the user sees while dragging is exactly where the icon lands.
    public static func move(_ id: String, toIndex index: Int, in order: [String]) -> [String] {
        guard let from = order.firstIndex(of: id) else { return order }
        var next = order
        next.remove(at: from)
        next.insert(id, at: min(max(index, 0), next.count))
        return next
    }
}

