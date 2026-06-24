import AppKit
import Carbon.HIToolbox
import SwiftUI

enum LaunchConstants {
    enum App {
        static let menuBarTitle = "L"
        static var settingsTitle: String { Localized.t("Launch 설정", "Launch Settings") }
        static let fallbackWindowFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    enum Menu {
        static var toggle: String { Localized.t("런처 토글", "Toggle Launch") }
        static var settings: String { Localized.t("설정", "Settings") }
        static var refreshApps: String { Localized.t("앱 새로고침", "Refresh Apps") }
        static var sortByName: String { Localized.t("이름순 정렬", "Sort by Name") }
        static var openApp: String { Localized.t("열기", "Open") }
        static var showInFinder: String { Localized.t("Finder에서 보기", "Show in Finder") }
        static var addToDock: String { Localized.t("Dock에 추가", "Add App to Dock") }
        static var hide: String { Localized.t("숨기기", "Hide") }
        static var removeFromFolder: String { Localized.t("폴더에서 제거", "Remove from Folder") }
        static var moveToTrash: String { Localized.t("휴지통으로 이동", "Move to Trash") }
        static var quit: String { Localized.t("종료", "Quit") }

        static let toggleKey = "l"
        static let settingsKey = ","
        static let refreshKey = "r"
        static let sortByNameKey = "s"
        static let quitKey = "q"
    }

    enum Alerts {
        static var cancel: String { Localized.t("취소", "Cancel") }
        static var moveToTrashFailed: String { Localized.t("앱을 휴지통으로 옮길 수 없습니다.", "Could not move app to Trash.") }

        static func moveToTrashTitle(appName: String) -> String {
            Localized.t("\"\(appName)\"을(를) 휴지통으로 옮길까요?", "Move \"\(appName)\" to Trash?")
        }
    }

    enum Settings {
        static var launchAtLogin: String { Localized.t("로그인 시 실행", "Launch at Login") }
        static var accessibility: String { Localized.t("손쉬운 사용", "Accessibility") }
        static var trackpad: String { Localized.t("트랙패드", "Trackpad") }
        static var globalHotKey: String { Localized.t("전역 단축키", "Global HotKey") }
        static var f4Key: String { Localized.t("F4 키", "F4 Key") }
        static var requestAccessibility: String { Localized.t("손쉬운 사용 권한 요청", "Request Accessibility Permission") }
        static var appearanceSection: String { Localized.t("모양", "Appearance") }
        static var generalSection: String { Localized.t("일반", "General") }
        static var permissionsSection: String { Localized.t("권한", "Permissions") }
        static var appSourcesSection: String { Localized.t("앱 소스", "App Sources") }
        static var gridLayoutSection: String { Localized.t("그리드 레이아웃", "Grid Layout") }
        static var backgroundTransparency: String { Localized.t("배경 투명도", "Background Transparency") }
        static var folderDim: String { Localized.t("폴더 어둡게", "Folder Dim") }
        static var backgroundTransparencyHelp: String { Localized.t("런처 뒤로 배경화면이 비치는 정도.", "How much of the wallpaper shows through the launcher.") }
        static var folderDimHelp: String { Localized.t("열린 폴더 뒤를 어둡게.", "Darkening behind an open folder.") }
        static var addAppSource: String { Localized.t("앱 소스 추가", "Add App Source") }
        static var removeAppSource: String { Localized.t("제거", "Remove") }
        static var gridPreset: String { Localized.t("그리드", "Grid") }
        static var importNativeLayout: String { Localized.t("기본 Launchpad 레이아웃 가져오기", "Import Native Launchpad Layout") }
        static var displayMode: String { Localized.t("표시 모드", "Display Mode") }
        static var windowBrowsingMode: String { Localized.t("창 탐색 모드", "Window Browsing Mode") }
        static var showMenuBarIcon: String { Localized.t("메뉴 막대 아이콘 표시", "Show Menu Bar Icon") }
        static var appIcon: String { Localized.t("앱 아이콘", "App Icon") }
        static var sortBy: String { Localized.t("정렬 기준", "Sort By") }

        static let width: CGFloat = 500
        static let height: CGFloat = 620
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

    /// Liquid Glass 튜닝 노브. 폴더 패널/타일은 `.clear` glassEffect에 시스템
    /// 스페큘러/엣지/굴절을 맡긴다 — 여기서 덧칠하지 않는다(우윳빛 카드 방지).
    /// 남은 건 패널 섀도 하나.
    enum Glass {
        static let panelShadowOpacity: CGFloat = 0.28
        static let panelShadowRadius: CGFloat = 28
        static let sheenOpacity: CGFloat = 0.04
        static let searchBarShadowOpacity: CGFloat = 0.15
        static let searchBarShadowRadius: CGFloat = 12
    }

    enum Storage {
        static let layoutOrderKey = "layoutOrder"
        static let foldersKey = "folders"
        static let appSourcesKey = "appSources"
        static let gridLayoutKey = "gridLayout"
        static let hiddenAppsKey = "hiddenApps"
        static let displayModeKey = "displayMode"
        static let windowBrowsingModeKey = "windowBrowsingMode"
        static let showMenuBarIconKey = "showMenuBarIcon"
        static let appIconKey = "appIcon"
        static let sortModeKey = "sortMode"
        static let appLanguageKey = "appLanguage"
    }

    enum Launcher {
        static var searchPlaceholder: String { Localized.t("검색", "Search") }
        static let pageSize = 35
        static let columns = 7
        static let rows = 5

        static let minHorizontalPadding: CGFloat = 60
        static let horizontalPaddingRatio: CGFloat = 0.08
        static let minTopInset: CGFloat = 44
        static let topInsetRatio: CGFloat = 1.0 / 14.0
        static let minBottomInset: CGFloat = 48
        static let bottomInsetRatio: CGFloat = 0.06
        static let menuBarReserve: CGFloat = 4
        static let searchToGridGap: CGFloat = 55
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
        static let dragEdgeWidth: CGFloat = 60
        static let dragPageScrollInterval: TimeInterval = 0.35 // Snappier scroll speed (0.35s instead of 0.8s)
    }

    enum Animation {
        /// Primary spring used by kristof12345/Launchpad and similar clones.
        static let spring = SwiftUI.Animation.interpolatingSpring(stiffness: 400, damping: 35)
        static let fade = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let quick = SwiftUI.Animation.easeOut(duration: 0.2)
        /// LaunchOS / native Launchpad open-close zoom.
        static let presentation = SwiftUI.Animation.interpolatingSpring(stiffness: 380, damping: 32)
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
        static let gridSpacing: CGFloat = 20
        static let spacing: CGFloat = 26
        static let titleFontSize: CGFloat = 25
        static let minGridHeight: CGFloat = 170
        static let padding: CGFloat = 36
        static let width: CGFloat = 600
        static let cornerRadius: CGFloat = 34
        static let maxIconSize: CGFloat = 86
        static let labelWidth: CGFloat = 104
    }

    enum Lifecycle {
        static let windowDuration: TimeInterval = 0.28
        static let hiddenScale: CGFloat = 0.94
    }

    enum WindowBrowsing {
        static let width: CGFloat = 980
        static let height: CGFloat = 720
        static let cornerRadius: CGFloat = 16
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
        static let triggerCooldown: Double = 0.65
    }
}
