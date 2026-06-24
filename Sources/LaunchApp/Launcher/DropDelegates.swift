import SwiftUI

struct AppDropDelegate: DropDelegate {
    let targetID: String
    var state: AppState

    func validateDrop(info: DropInfo) -> Bool {
        state.canDropApp(on: targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .cancel)
    }

    func dropEntered(info: DropInfo) {
        if let dragged = state.draggedAppID {
            LaunchLog.line("app drop entered dragged=\(dragged) target=\(targetID)")
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = state.draggedAppID, validateDrop(info: info) else {
            state.cancelDrag()
            return false
        }
        LaunchLog.line("app drop perform dragged=\(dragged) target=\(targetID)")
        state.dropApp(dragged, on: targetID)
        state.draggedAppID = nil
        return true
    }
}

struct FolderDropDelegate: DropDelegate {
    let targetID: String
    var state: AppState

    func validateDrop(info: DropInfo) -> Bool {
        state.canDropApp(on: targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .cancel)
    }

    func dropEntered(info: DropInfo) {
        if let dragged = state.draggedAppID {
            LaunchLog.line("folder drop entered dragged=\(dragged) target=\(targetID)")
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = state.draggedAppID, validateDrop(info: info) else {
            state.cancelDrag()
            return false
        }
        LaunchLog.line("folder drop perform dragged=\(dragged) target=\(targetID)")
        state.dropApp(dragged, on: targetID)
        state.draggedAppID = nil
        return true
    }
}
