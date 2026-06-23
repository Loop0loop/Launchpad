import AppKit
import Carbon.HIToolbox
import SwiftUI

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
        static let sortByName = "Sort by Name"
        static let openApp = "Open"
        static let showInFinder = "Show in Finder"
        static let addToDock = "Add App to Dock"
        static let hide = "Hide"
        static let moveToTrash = "Move to Trash"
        static let quit = "Quit"

        static let toggleKey = "l"
        static let settingsKey = ","
        static let refreshKey = "r"
        static let sortByNameKey = "s"
        static let quitKey = "q"
    }

    enum Alerts {
        static let cancel = "Cancel"
        static let moveToTrashFailed = "Could not move app to Trash."

        static func moveToTrashTitle(appName: String) -> String {
            "Move \"\(appName)\" to Trash?"
        }
    }

    enum Settings {
        static let launchAtLogin = "Launch at Login"
        static let accessibility = "Accessibility"
        static let trackpad = "Trackpad"
        static let globalHotKey = "Global HotKey"
        static let f4Key = "F4 Key"
        static let requestAccessibility = "Request Accessibility Permission"
        static let appearanceSection = "Appearance"
        static let generalSection = "General"
        static let permissionsSection = "Permissions"
        static let appSourcesSection = "App Sources"
        static let gridLayoutSection = "Grid Layout"
        static let backgroundTransparency = "Background Transparency"
        static let folderDim = "Folder Dim"
        static let backgroundTransparencyHelp = "How much of the wallpaper shows through the launcher."
        static let folderDimHelp = "Darkening behind an open folder."
        static let addAppSource = "Add App Source"
        static let removeAppSource = "Remove"
        static let gridPreset = "Grid"
        static let importNativeLayout = "Import Native Launchpad Layout"
        static let displayMode = "Display Mode"
        static let windowBrowsingMode = "Window Browsing Mode"

        static let width: CGFloat = 420
        static let height: CGFloat = 560
        static let padding: CGFloat = 24
        static let sectionSpacing: CGFloat = 18
        static let cardCornerRadius: CGFloat = 16
        static let titleBarInset: CGFloat = 36
    }

    enum Appearance {
        static let maxBackgroundDim = 0.45
        static let minFolderDim = 0.08
        static let maxFolderDim = 0.55
        static let defaultBackgroundTransparency = 0.85
        static let defaultFolderDimOpacity = 0.28
        static let settingsBackdropOpacity = 0.18
    }

    enum Storage {
        static let layoutOrderKey = "layoutOrder"
        static let foldersKey = "folders"
        static let appSourcesKey = "appSources"
        static let gridLayoutKey = "gridLayout"
        static let hiddenAppsKey = "hiddenApps"
        static let displayModeKey = "displayMode"
        static let windowBrowsingModeKey = "windowBrowsingMode"
    }

    enum Launcher {
        static let searchPlaceholder = "Search"
        static let pageSize = 35
        static let columns = 7
        static let rows = 5

        static let minHorizontalPadding: CGFloat = 60
        static let horizontalPaddingRatio: CGFloat = 0.08
        static let minTopInset: CGFloat = 52
        static let topInsetRatio: CGFloat = 1.0 / 14.0
        static let minBottomInset: CGFloat = 72
        static let bottomInsetRatio: CGFloat = 0.1
        static let menuBarReserve: CGFloat = 12
        static let searchToGridGap: CGFloat = 20
        static let gridToPagerGap: CGFloat = 16
        static let minGridHeight: CGFloat = 240

        static let gridSpacing: CGFloat = 24
        static let minGridRowSpacing: CGFloat = 16
        static let iconColumnScale: CGFloat = 0.78
        static let iconRowScale: CGFloat = 0.58
        static let minIconSize: CGFloat = 80
        static let maxIconSize: CGFloat = 112

        static let searchWidth: CGFloat = 300
        static let searchHeight: CGFloat = 36
        static let searchHorizontalPadding: CGFloat = 14
        static let searchFontSize: CGFloat = 15

        static let backgroundMaterial: NSVisualEffectView.Material = .fullScreenUI
        static let backgroundOpacity = 0.06
        static let overlayOpacity = 0.28

        static let pageDotSize: CGFloat = 8
        static let pageDotSpacing: CGFloat = 8
        static let pageControlHeight: CGFloat = 20
        static let inactivePageOpacity = 0.35
        static let pageIndicatorActiveScale: CGFloat = 1.25

        static let dragMinimumDistance: CGFloat = 12
        static let pageDragThreshold: CGFloat = 60
        static let pageSwipeThresholdRatio: CGFloat = 0.15
        static let pageRubberBandRatio: CGFloat = 0.25
        static let pageChangeCooldown: TimeInterval = 0.35
        static let folderEntranceScale: CGFloat = 0.85
    }

    enum Animation {
        /// Primary spring used by kristof12345/Launchpad and similar clones.
        static let spring = SwiftUI.Animation.interpolatingSpring(stiffness: 400, damping: 35)
        static let fade = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let quick = SwiftUI.Animation.easeOut(duration: 0.2)
    }

    enum Icon {
        static let maxLabelWidth: CGFloat = 120
        static let labelHeight: CGFloat = 34
        static let labelFontSize: CGFloat = 13
        static let spacing: CGFloat = 8
        static let draggedOpacity = 0.35
        static let folderCornerRadius: CGFloat = 18
        static let folderFillOpacity = 0.14
        static let folderPreviewColumns = 2
        static let folderPreviewLimit = 4
        static let folderPreviewScale: CGFloat = 0.28
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
        static let maxIconSize: CGFloat = 88
        static let labelWidth: CGFloat = 104
    }

    enum Lifecycle {
        static let windowDuration: TimeInterval = 0.25
    }

    enum WindowBrowsing {
        static let width: CGFloat = 980
        static let height: CGFloat = 720
    }

    enum HotKey {
        static let signature: OSType = 0x4C6E6368
        static let toggleID: UInt32 = 1
        static let f4ID: UInt32 = 2
        static let toggleKeyCode: UInt32 = UInt32(kVK_Space)
        static let toggleModifiers: UInt32 = UInt32(controlKey | optionKey)
        static let f4KeyCode: UInt32 = UInt32(kVK_F4)
        static let f4Modifiers: UInt32 = 0
    }

    enum HotCorner {
        static let activationSize: CGFloat = 6
        static let pollInterval: TimeInterval = 0.12
        static let cooldown: TimeInterval = 1.0
    }

    enum Multitouch {
        static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        static let createListSymbol = "MTDeviceCreateList"
        static let registerContactFrameCallbackSymbol = "MTRegisterContactFrameCallback"
        static let deviceStartSymbol = "MTDeviceStart"
        static let gestureFingerCount = 4
        static let pinchInRatio = 0.9
        static let pinchOutRatio = 1.1
        static let triggerCooldown: Double = 0.25
    }
}
