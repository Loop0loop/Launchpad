import LaunchpadCore

@MainActor
struct LauncherActions {
    var close: () -> Void = {}
    var dismiss: () -> Void = {}
    var canHandleUserDismissal: () -> Bool = { true }
    var launch: (LaunchApp) -> Void = { _ in }
    var showInFinder: (LaunchApp) -> Void = { _ in }
    var moveToTrash: (LaunchApp) -> Void = { _ in }
    var addToDock: (LaunchApp) -> Void = { _ in }
    var chooseAppSource: () -> Void = {}
    var applyWindowBrowsingMode: () -> Void = {}
    var applyMenuBarVisibility: () -> Void = {}
    var applyAppIcon: () -> Void = {}
    var applyInputSettings: () -> Void = {}
    var clearIconCache: () -> Void = {}
    var restoreLauncherRoot: () -> Void = {}
    var releaseLauncherRoot: () -> Void = {}
}
