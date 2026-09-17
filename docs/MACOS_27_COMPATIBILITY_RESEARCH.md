# macOS 26 → 27 제스처·드래그 호환성 조사

조사일: 2026-09-17  
기준 커밋: `78bac765cd16` (`main`)  
현재 환경: macOS 27.0 (`26A428`), Xcode 27.0 (`27A266a`), macOS SDK 27.0, Swift 6.4  
패키지 배포 대상: macOS 27 (`swift-tools-version: 6.4`)

## 적용 상태

- 버전: Xcode 27.0 / macOS SDK 27.0 / Swift 6.4에 맞춰 Swift tools와 최소 배포 대상을 27로 올렸다.
- A: drag session ID, 단조 시각, 시작·페이지 전환·소스 뷰 소멸·취소 사유 로그를 추가했다.
- B: 루트 앱/폴더 타일의 SwiftUI `DragGesture`를 `NSGestureRecognizerRepresentable` + `NSDraggingSession`으로 교체했다. 가장자리 페이지 타이머도 장수명 drag controller가 소유한다.
- C: 앱 실행 중에는 사용자 설정을 저장한 뒤 `showSpotlightGestureEnabled=0`, `showDesktopGestureEnabled=1`, 물리 4/5손가락 핀치=0으로 예약한다. 종료하면 값의 부재까지 포함해 원래 설정을 복원한다.
- D: 포인터 위치 관찰을 들린 아이콘 하나로 제한하고 페이지 offset을 보정해 페이지 이동 중 고스트가 포인터에서 이탈하지 않게 했다. 원래 셀은 옅은 gap으로 남고 들린 아이콘에는 크기·투명도·그림자 피드백을 준다.
- E: 시스템 설정의 Apps/Show Desktop 조합과 관계없이 앱이 물리 핀치를 독점한다. 일반 화면의 오므리기는 커스텀 런치패드로, 펼치기와 데스크탑 복귀는 연속 Dock Swipe HID 이벤트로 한 경로만 출력한다.
- F: 접촉 직후 provisional 프레임에서는 기준점을 잡지 않고 20ms 안정화 뒤 판정을 시작한다. 방향 확정 최소 변화를 1%에서 2.5%로 올려 손가락 착지 반동이 반대 제스처로 고정되는 문제를 막았다.
- 검증: `swift build`, `swift run LaunchpadCheck`, `swift test` 62개, 개발 앱 빌드·서명 검증을 통과했다.
- 런타임: 사용자 상태가 Show Desktop=0, 물리 핀치=0일 때 실행 중 Apps=0 / Dock Show Desktop action=1 / 물리 핀치=0 조합과 `continuous` 모드가 초기화됐다. 종료 뒤 Show Desktop과 물리 핀치가 모두 0으로 복원되는 것도 확인했다.

실제 포인터로 앱/폴더를 여러 번 끌고 페이지 1↔2를 넘기는 수동 검증과 트랙패드 네 조합 검증은 남아 있다.

## 결론

세 증상은 하나의 Swift 언어 변경으로 설명되지 않는다.

1. 앱/폴더 드래그 중단과 런처 페이지 이동 실패는 변경 전 구현이 시스템 드래그 세션이 아니라, 이동·재구성되는 SwiftUI 아이콘 뷰의 `DragGesture` 생명주기에 의존했기 때문에 발생할 가능성이 높다. macOS 27은 AppKit 제스처의 뷰 계층 독점 규칙과 멈춘 제스처 자동 취소를 명시적으로 도입했다.
2. 런처의 1페이지→2페이지 이동 실패는 드래그 도중 `currentPage`와 렌더링 페이지 집합을 바꾸면서 소스 SwiftUI 뷰까지 재구성하던 경로가 직접적인 취소 지점이었다.
3. 트랙패드 문제는 Swift보다 비공개 설정 의존성 문제다. macOS 27 Trackpad Settings 확장에는 기존 `showLaunchpadGestureEnabled` 대신 `showSpotlightGestureEnabled`가 들어 있다. Show Desktop이 꺼진 경우에는 펼치기를 넘겨받을 시스템 동작도 사라지므로 앱이 직접 출력까지 맡아야 한다.

Apple의 Xcode 27 및 macOS 27 릴리스 노트에서 `SwiftUI.DragGesture` 자체의 호환성 중단 선언은 찾지 못했다. 따라서 “Swift 6.4가 드래그를 깨뜨렸다”라고 결론 내릴 근거는 없다. 확인된 변화는 AppKit의 제스처 전달·취소 규칙과 새 드래그 API다.

## 증상별 조사 결과

| 증상 | 코드에서 확인된 원인 | macOS 27 변화와의 관계 | 확신도 |
| --- | --- | --- | --- |
| 드래그가 중간에 끊김 | 변경 전 앱/폴더 모두 아이콘 뷰에 붙은 `DragGesture`를 사용했다. `@GestureState`가 `true→false`가 되면 즉시 드래그 상태를 취소했다. | 27은 최초 hit-test 뷰 계층의 제스처만 활성화하는 독점 규칙과 멈춘 제스처의 시간 초과 취소를 도입했다. 페이지/폴더 전환으로 소스 뷰가 바뀌면 기존보다 취소가 쉽게 드러날 수 있다. | 코드 구조: 높음, 정확한 런타임 촉발 조건: 중간 |
| 런처 1페이지→2페이지 이동 불가 | 변경 전 가장자리 체류 타이머가 드래그 중 `selectPage`를 호출하면서 `PagedGridView`의 아이콘 소스 뷰도 함께 재구성했다. | 활성 제스처가 붙은 뷰의 정체성·계층이 바뀌는 패턴이 27의 제스처 독점/종료 규칙과 충돌할 수 있다. | 높음 |
| Apps/데스크탑 보기 설정 결합 | 변경 전 코드가 폐기된 `showLaunchpadGestureEnabled`를 썼다. | 27 Trackpad Settings 확장은 Open Apps에 `showSpotlightGestureEnabled`를 사용하고 Show Desktop에는 `showDesktopGestureEnabled`를 사용한다. | 키 변경: 높음, 두 설정의 실제 런타임 독립성: 실기 확인 필요 |

## 1. 변경 전 드래그가 중간에 끊기던 경로

변경 전 루트 앱과 폴더 아이콘의 드래그는 [LauncherItemViews.swift](../Sources/LaunchApp/Launcher/LauncherItemViews.swift)의 `LauncherDragModifier`가 처리했다.

- `DragGesture(minimumDistance: 8, coordinateSpace: .named("launcherGrid"))`를 각 아이콘 뷰에 붙였다.
- 드래그가 시작되면 원본 아이콘을 투명하게 만들고 같은 뷰 계층에 떠 있는 복사본을 그렸다.
- `@GestureState isDragActive`가 `true`에서 `false`로 바뀌었는데 정상 종료 처리가 끝나지 않았다면 `cancelDrag()`를 호출했다.

폴더 안 앱도 [FolderOverlay.swift](../Sources/LaunchApp/Launcher/FolderOverlay.swift)에서 같은 형태의 `DragGesture`와 `@GestureState` 취소 감지를 사용한다. 따라서 앱과 폴더에서 같은 증상이 나는 것은 현재 구조와 일치한다.

이 구현은 AppKit의 `NSDraggingSession`이나 SwiftUI의 `.draggable`/`.dropDestination`을 사용하지 않았다. 시스템이 소스 뷰와 별개로 유지하는 드래그 세션이 없으므로, 소스 아이콘 뷰가 교체되거나 제스처 인식기가 취소되면 전체 드래그가 끝났다.

macOS 27 릴리스 노트는 다음 AppKit 제스처 동작을 새로 명시한다.

- 최초 터치가 hit-test한 뷰 계층만 모든 제스처가 끝날 때까지 인식기를 활성화한다.
- `NSView.exclusiveGestureBehavior`와 앱 전체 `NSViewGestureRecognizerIsExclusive` 설정으로 이 동작을 조정할 수 있다.
- 입력 없이 멈춘 독점 제스처는 몇 초 뒤 자동 취소된다.
- 진단용 `NSCrashOnStuckGestureTimeout` 기본값을 제공한다.
- `NSGestureRecognizer.isCancellableByScrollGesture`를 추가했다.

출처: [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes), [TN3212: Adopting gesture recognizers for Sidecar touch support](https://developer.apple.com/documentation/technotes/tn3212-adopting-gesture-recognizers-for-sidecar-touch-support)

변경 전 코드는 같은 입력을 SwiftUI `DragGesture`, `NSEvent` 로컬 mouse 모니터, 페이지 스와이프/스크롤 감시기가 함께 관찰했다. 페이지 재구성으로 SwiftUI 인식기가 이벤트를 잃으면 27의 자동 취소가 최종 증상으로 나타날 수 있다. 이 연결은 코드와 Apple 문서에 근거한 추론이며, 정확한 런타임 촉발 조건까지 확정하려면 재현 로그가 필요하다.

## 2. 런처 페이지 이동

### 런처 페이지 1 → 2

변경 전 [LauncherMouseMonitor.swift](../Sources/LaunchApp/Input/LauncherMouseMonitor.swift)는 아이콘 드래그가 화면 가장자리에 머무르면 약 0.45초 뒤 `selectPage()`를 호출했다. 적용 후 이 타이머는 `LauncherNativeDragController`가 소유하며 이후 0.9초 간격으로 계속 넘길 수 있다.

[LauncherContent.swift](../Sources/LaunchApp/Launcher/LauncherContent.swift)의 `PagedGridView`는 드래그가 시작되면 근처 페이지만 그리던 상태에서 모든 페이지를 렌더링하도록 바꾼다. 페이지를 넘길 때는 다음 값이 동시에 바뀐다.

- `currentPage`
- 모든 페이지의 x offset
- `LazyVGrid`에 들어가는 아이템 배열과 삽입 위치
- 드래그 중인 아이콘 뷰가 속한 페이지/셀

변경 전에는 활성 `DragGesture`의 소스 뷰를 움직이거나 다시 만드는 경로였으므로, 페이지 전환 직후 `isDragActive`가 false가 되고 `cancelDrag()`로 이어질 수 있었다. 적용 후에는 같은 UI 재배치 중에도 AppKit 세션과 controller가 소스 생명주기를 유지한다.

## 3. macOS 27의 드래그 관련 새 API

Apple은 macOS 27에 제스처 인식기에서 네이티브 드래그를 시작하는 `NSView.beginDraggingSession(items:gesture:source:)`를 추가했다. `NSDraggingSession`은 소스 뷰의 SwiftUI 상태와 별개로 드래그 생명주기, 위치, 취소/실패 애니메이션과 source callback을 관리한다.

출처: [AppKit updates](https://developer.apple.com/documentation/updates/appkit), [`NSDraggingSession`](https://developer.apple.com/documentation/appkit/nsdraggingsession), [Apple TN3212](https://developer.apple.com/documentation/technotes/tn3212-adopting-gesture-recognizers-for-sidecar-touch-support)

SwiftUI 27에는 임의의 `ForEach`/grid에서 쓰는 `.reorderable()`과 `.reorderContainer()`도 추가됐다. 시스템이 드래그 원본을 들어 올리고 placeholder를 유지하며, 여러 collection 사이 이동도 처리한다.

출처: [Reordering items in lists, stacks, grids, and custom layouts](https://developer.apple.com/documentation/swiftui/reordering-items-in-lists-stacks-grids-and-custom-layouts), [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui)

이 프로젝트에는 단순 정렬 외에 앱 위 dwell, 폴더 생성, 폴더 추가, 폴더 자동 열기, 페이지 이동이 있으므로 `.reorderable()`로 즉시 전환할 수 있다고 단정할 수 없다. 가장 작은 검증은 다음 두 후보의 짧은 프로토타입이다.

1. `NSGestureRecognizerRepresentable` + `beginDraggingSession(items:gesture:source:)`로 현재 hit-test와 폴더 규칙을 유지하면서 생명주기만 시스템에 맡긴다.
2. `.reorderable()`이 폴더 생성 dwell과 다중 페이지 collection을 표현할 수 있는지 별도 샘플에서 확인한다.

1번이 현재 도메인 규칙을 덜 바꾸는 경로여서 적용했다. 내부 이동 payload는 프로젝트 규칙대로 외부 앱이 사용할 수 없는 private in-process pasteboard type을 사용한다.

패키지 배포 대상을 macOS 27로 올렸으므로 27 전용 `beginDraggingSession(items:gesture:source:)`와 SwiftUI reorder API를 직접 사용할 수 있다.

## 4. 트랙패드 Apps / Show Desktop 설정

공개 사용자 문서상 macOS 26과 27 모두 네 손가락 또는 다섯 손가락 오므리기를 “Open Apps”로 설명하며 Spotlight의 Apps 화면을 연다. “Show Desktop”은 별도 펼치기 제스처로 설명한다. macOS 27의 앱 브라우저 자체도 Spotlight 안의 Apps 화면으로 문서화되어 있다.

출처: [macOS 26 MacBook Air trackpad guide](https://support.apple.com/en-gb/guide/macbook-air/apdbb563a1bc/2026/mac/26), [macOS 27 Magic Trackpad guide](https://support.apple.com/guide/imac/magic-trackpad-apdea23385dd/2026/mac/27), [Change Trackpad settings](https://support.apple.com/guide/mac-help/change-trackpad-settings-mchlp1226/mac), [View and open apps on Mac](https://support.apple.com/guide/mac-help/mh35840/mac)

그러나 Apple 공개 개발자 문서에는 앱이 Open Apps/Show Desktop 시스템 제스처를 켜고 끄거나, 두 방향을 독립적으로 예약하는 API가 없다.

현재 구현은 다음 비공개 요소에 의존한다.

- [TrackpadGestureMonitor.swift](../Sources/LaunchApp/Input/TrackpadGestureMonitor.swift): `/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport`를 `dlopen`하고 `MTDeviceCreateList`, `MTRegisterContactFrameCallback`, `MTDeviceStart` ABI를 직접 선언한다.
- [SystemTrackpadSettings.swift](../Sources/LaunchApp/Input/SystemTrackpadSettings.swift): 원래 Dock action과 물리 핀치 값을 원자적으로 저장한다. 실행 중 Apps action은 끄고 Dock의 Show Desktop action만 켜되, 시스템이 같은 손동작을 직접 처리하지 않도록 물리 핀치는 0으로 예약한다. 구형 `showLaunchpadGestureEnabled` 스냅샷도 한 번 복원한 뒤 제거한다.
- [SystemShowDesktopController.swift](../Sources/LaunchApp/Input/SystemShowDesktopController.swift): Accessibility 알림으로 실제 데스크탑 상태를 관찰한다. 시스템 설정이 꺼진 경우 macOS 27 Dock Swipe HID 이벤트를 출력하며, HID 경로를 사용할 수 없을 때만 `CoreDockSendNotification`을 완료 시점 fallback으로 사용한다.
- [LaunchDockSwipe.m](../Sources/LaunchAppPrivateSupport/LaunchDockSwipe.m): 타입 30 `CGEvent`에 Dock Swipe 타입 23 HID payload를 붙인다. phase, pinch motion, 누적 progress와 terminal velocity를 `SLEventSetIOHIDEvent`로 전달한다.
- 같은 파일에서 비공개 `activateSettings -u`, `notifyutil`, `launchctl kickstart -k .../com.apple.Dock.agent`로 적용을 시도한다.

현재 macOS 27 환경의 읽기 전용 확인 결과는 다음과 같다.

```text
com.apple.dock.showSpotlightGestureEnabled = 값 없음(기본 활성)
com.apple.dock.showLaunchpadGestureEnabled = 값 없음(구형 키)
com.apple.dock.showDesktopGestureEnabled = 1
TrackpadFourFingerPinchGesture = 2
TrackpadFiveFingerPinchGesture = 2
com.apple.trackpad.fourFingerPinchSwipeGesture = 0
com.apple.trackpad.fiveFingerPinchSwipeGesture = 0
```

macOS 27의 `/System/Library/ExtensionKit/Extensions/TrackpadExtension.appex`를 읽기 전용으로 조사한 결과 `showSpotlightGestureEnabled`와 `showDesktopGestureEnabled`가 각각 포함되어 있다. 기존 `showLaunchpadGestureEnabled` 문자열은 이 확장과 Dock 실행 파일에서 발견되지 않았다. 두 action key를 분리해 쓰면 설정 UI가 허용하지 않는 Apps=0 / Show Desktop=1 조합을 앱 실행 중에만 구성할 수 있다. 물리 핀치는 별도로 0으로 예약하므로 네이티브 Launchpad나 Show Desktop이 동시에 반응하지 않는다.

이 키들과 `CoreDock*` 함수는 공개 API가 아니다. 이번 macOS 27 빌드에서 심볼과 호출 성공은 확인했지만 다음 macOS 빌드에서도 ABI가 유지된다는 보장은 없다.

## 적용 순서와 확인사항

### A. 드래그 취소 계측

macOS 27 개발 번들에 drag session ID와 아래 진단 로그를 추가했다.

- 시작, 소스 아이콘 `onDisappear`, 현재 런처 페이지와 페이지 전환
- 성공, 실패, ESC, 새 mouse-down, launcher hide 등 종료 사유
- 프로세스 ID와 단조 시각

`NSCrashOnStuckGestureTimeout`은 기존 SwiftUI 제스처의 자동 취소 스택이 추가로 필요할 때만 개발 실행에 사용한다.

### B. 드래그 생명주기를 시스템에 맡기기

루트 앱/폴더 타일의 도메인 상태는 유지하고 포인터 드래그 생명주기를 `NSDraggingSession`으로 옮겼다. 페이지를 넘기거나 폴더 overlay를 열어도 장수명 controller가 세션을 유지한다. 폴더 overlay 내부 재정렬과 pull-out은 기존 별도 상태 경로를 유지한다.

런처 페이지 변경은 네이티브 세션이 활성화된 뒤 허용한다.

### C. macOS 27 Spotlight Apps 키로 전환

macOS 27에서는 구형 `showLaunchpadGestureEnabled`를 생성하지 않고 `showSpotlightGestureEnabled`만 저장·비활성화·복원한다. 남은 실기 확인에서는 아래 네 조합을 System Settings UI와 실제 동작으로 기록해야 한다.

| Apps | Show Desktop | 확인할 동작 |
| --- | --- | --- |
| 끔 | 끔 | 두 방향 모두 시스템 동작 없음 |
| 켬 | 끔 | 오므리기만 Apps 열기 |
| 끔 | 켬 | UI에서 가능한지, 재로그인/Dock 재시작 뒤 유지되는지 |
| 켬 | 켬 | 오므리기 Apps, 펼치기 Desktop, 복귀 오므리기 충돌 여부 |

공개 API만으로 이 조합을 보장할 방법은 확인되지 않았다. 구현은 사용자 설정과 관계없이 실행 중 물리 핀치를 독점하고, Dock의 Show Desktop action만 합성 이벤트의 대상으로 활성화한다. 출력은 `began → changed → ended/cancelled` 상태와 누적 진행률을 Dock에 전달하므로 창 이동과 되감기, 손을 뗀 뒤의 정착은 macOS가 처리한다. 종료 시 원래 action과 물리 핀치 값을 복원한다.

## 5. 연속 제스처 조사 결과

Apple 공개 문서로 확인되는 계약은 다음 범위다.

- AppKit의 연속 인식기는 `possible → began → changed → ended/cancelled` 상태로 진행하며 `changed`마다 앱이 표현 상태를 갱신할 수 있다.
- `NSMagnificationGestureRecognizer.magnification`은 현재 확대량을 연속값으로 제공한다.
- HIG는 제스처 수행 중 즉시 피드백하고 결과를 되돌릴 수 있어야 한다고 설명한다.
- `CASpringAnimation`은 mass, stiffness, damping, initial velocity로 release 뒤 정착을 표현한다.

출처: [NSGestureRecognizer](https://developer.apple.com/documentation/appkit/nsgesturerecognizer), [NSMagnificationGestureRecognizer magnification](https://developer.apple.com/documentation/appkit/nsmagnificationgesturerecognizer/magnification), [Apple HIG Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures), [Apple HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion), [CASpringAnimation damping](https://developer.apple.com/documentation/quartzcore/caspringanimation/damping)

Apple은 Show Desktop의 진행률을 직접 제어하는 공개 API를 제공하지 않는다. macOS 27에서 확인된 실제 출력 경로는 비공개 Dock Swipe HID 이벤트다. Mac Mouse Fix의 macOS 27 구현은 `CGEvent` 필드가 무시되므로 타입 23 `HIDEvent`가 필요하다고 기록하며, progress와 terminal velocity를 함께 보낸다. 별도 macOS 27 호환 프로젝트도 `SLEventSetIOHIDEvent`로 같은 payload를 부착하고 진행률과 속도의 부호를 함께 정규화해야 release 반동을 막는다고 보고한다.

참고 구현: [Mac Mouse Fix TouchSimulator](https://github.com/noah-nuebling/mac-mouse-fix/blob/master/Helper/Core/Touch/TouchSimulator.m), [MMF27 Dock Swipe Fix](https://github.com/timmyagentic/mac-mouse-fix-macos-27-fix), [dockswipe](https://github.com/oomol-lab/dockswipe)

사용자가 제시한 정전용량 히트맵, palm rejection, 접촉 clustering, 머신러닝 분류라는 하드웨어/OS 내부 설명은 일반적인 입력 처리 모델로는 타당하지만 Apple 공개 문서에서 macOS 트랙패드의 정확한 구현으로 확인되지는 않았다. 이번 수정은 검증 가능한 접촉 ID·상태·기하 변화와 공식 연속 제스처 상태 모델만 입력 규칙으로 사용한다. 스프링 정착은 별도로 흉내 내지 않고 Dock에 진행률과 속도를 전달해 시스템 구현에 맡긴다.

## 회귀 검증 매트릭스

| 영역 | macOS 26 | macOS 27 |
| --- | --- | --- |
| 앱/폴더 루트 reorder 20회 | 성공/취소/ghost 기록 | 동일 |
| 앱→앱 폴더 생성, 앱→폴더 추가 | 성공/취소/opacity 복원 | 동일 |
| 폴더 내부 reorder와 pull-out | 성공/취소/overlay 상태 | 동일 |
| 페이지 1↔2 가장자리 이동 | 양방향 연속 10회 | 동일 + 취소 시간 기록 |
| ESC/실패 drop/마우스 취소 | transient state와 opacity 복원 | 동일 |
| Apps/Show Desktop 네 조합 | 설정 UI·재로그인·Dock 재시작 | 동일 |
| 내부/외장 트랙패드 | 각각 검사 | 각각 검사 |

## 조사 한계

- Apple은 `showSpotlightGestureEnabled`, `showLaunchpadGestureEnabled`, 물리 핀치 기본값과 Dock 알림의 의미를 공개 API로 문서화하지 않는다.
- macOS 27 릴리스 노트는 AppKit 제스처 규칙 변화를 문서화하지만, SwiftUI `DragGesture` 취소와 이 프로젝트의 페이지 재구성을 직접 연결해 설명하지 않는다. 그 연결은 재현 계측으로 확정해야 한다.
- 코드·시스템 조사 뒤 A→B→C 구현과 자동 검증을 완료했다. 실제 포인터 및 트랙패드 조작 결과는 아직 기록하지 않았으므로 표의 실기 항목은 남아 있다.
