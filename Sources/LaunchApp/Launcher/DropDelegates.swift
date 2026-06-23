import SwiftUI

struct AppDropDelegate: DropDelegate {
    let targetID: String
    @ObservedObject var state: AppState

    func dropEntered(info: DropInfo) {
        guard let dragged = state.draggedAppID else { return }
        state.move(dragged, before: targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        if let dragged = state.draggedAppID {
            state.dropApp(dragged, on: targetID)
        }
        state.draggedAppID = nil
        return true
    }
}

struct FolderDropDelegate: DropDelegate {
    let targetID: String
    @ObservedObject var state: AppState

    func dropEntered(info: DropInfo) {
        guard let dragged = state.draggedAppID else { return }
        state.move(dragged, before: targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        state.draggedAppID = nil
        return true
    }
}

