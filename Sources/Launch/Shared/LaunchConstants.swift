import AppKit

enum LaunchConstants {
    enum App {
        static let menuBarTitle = "L"
        static let settingsTitle = "Launch Settings"
        static let fallbackWindowFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    enum Menu {
        static let toggle = "Toggle Launch"
        static let settings = "Settings"
        static let refreshApps = "Refresh Apps"
        static let quit = "Quit"

        static let toggleKey = "l"
        static let settingsKey = ","
        static let refreshKey = "r"
        static let quitKey = "q"
    }

    enum Settings {
        static let launchAtLogin = "Launch at Login"
        static let accessibility = "Accessibility"
        static let trackpad = "Trackpad"
        static let requestAccessibility = "Request Accessibility Permission"

        static let width: CGFloat = 360
        static let height: CGFloat = 180
        static let padding: CGFloat = 24
    }

    enum Storage {
        static let layoutOrderKey = "layoutOrder"
        static let foldersKey = "folders"
    }

    enum Launcher {
        static let searchPlaceholder = "Search Applications"
        static let pageSize = 35
        static let columns = 7
        static let gridItemWidth: CGFloat = 112
        static let gridSpacing: CGFloat = 18
        static let gridRowSpacing: CGFloat = 22
        static let verticalSpacing: CGFloat = 34
        static let gridHeight: CGFloat = 620
        static let topPadding: CGFloat = 70
        static let searchWidth: CGFloat = 420
        static let searchHeight: CGFloat = 44
        static let searchHorizontalPadding: CGFloat = 18
        static let searchFontSize: CGFloat = 18
        static let backgroundOpacity = 0.22
        static let overlayOpacity = 0.28
        static let pageDotSize: CGFloat = 7
        static let pageDotSpacing: CGFloat = 8
        static let pageDotHeight: CGFloat = 14
        static let inactivePageOpacity = 0.35
        static let contentHiddenScale = 0.96
        static let pageTransitionScale = 0.985
        static let contentAnimationDuration = 0.18
        static let pageAnimationDuration = 0.16
        static let dragMinimumDistance: CGFloat = 40
        static let pageDragThreshold: CGFloat = 60
    }

    enum Icon {
        static let imageSize: CGFloat = 72
        static let miniImageSize: CGFloat = 22
        static let miniGridItemWidth: CGFloat = 24
        static let labelWidth: CGFloat = 104
        static let labelHeight: CGFloat = 34
        static let labelFontSize: CGFloat = 13
        static let spacing: CGFloat = 8
        static let draggedOpacity = 0.35
        static let folderCornerRadius: CGFloat = 18
        static let folderPreviewColumns = 2
        static let folderPreviewLimit = 4
    }

    enum FolderOverlay {
        static let columns = 4
        static let gridItemWidth: CGFloat = 112
        static let gridSpacing: CGFloat = 18
        static let spacing: CGFloat = 22
        static let titleFontSize: CGFloat = 24
        static let minGridHeight: CGFloat = 150
        static let padding: CGFloat = 30
        static let width: CGFloat = 560
        static let cornerRadius: CGFloat = 24
    }

    enum Lifecycle {
        static let showDuration = 0.16
        static let hideDuration = 0.12
    }

    enum Multitouch {
        static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        static let createListSymbol = "MTDeviceCreateList"
        static let registerContactFrameCallbackSymbol = "MTRegisterContactFrameCallback"
        static let deviceStartSymbol = "MTDeviceStart"
        static let fourFingerCount: Int32 = 4
    }
}
