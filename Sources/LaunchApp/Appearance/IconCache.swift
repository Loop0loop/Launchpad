import AppKit
import LaunchpadCore
import SwiftUI

/// 아이콘 로드를 메인 스레드에서 분리한다.
/// (1) 메모리 LRU hit → 즉시 반환, (2) miss → placeholder(nil) 즉시 반환 + 백그라운드 로드 예약,
/// (3) 백그라운드: 디스크 캐시 → `NSWorkspace.icon`. 로드 완료 시 `generation`을 올려 관찰 뷰 갱신.
@MainActor
final class IconCache: ObservableObject {
    @Published private(set) var generation = 0

    private var memory: [String: NSImage] = [:]
    private var lru: [String] = []
    private var loading: Set<String> = []
    private let limit = 160
    private let diskDir: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("Launch/icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.diskDir = dir
    }

    /// 캐시에 있으면 즉시 반환. 없으면 nil(placeholder)을 주고 백그라운드 로드를 예약한다.
    func icon(for app: LaunchApp, size: CGFloat = LaunchConstants.Launcher.maxIconSize) -> NSImage? {
        let key = app.path
        if let cached = memory[key] {
            markRecent(key)
            return cached
        }
        ensureLoaded(path: key, size: size)
        return nil
    }

    func clear() {
        memory.removeAll()
        lru.removeAll()
        loading.removeAll()
        generation &+= 1
    }

    private func ensureLoaded(path: String, size: CGFloat) {
        guard !loading.contains(path), memory[path] == nil else { return }
        loading.insert(path)
        let cacheURL = diskDir.appendingPathComponent(Self.diskKey(path: path, size: size))
        Task.detached(priority: .utility) { [weak self] in
            let image = Self.loadFromDisk(url: cacheURL, size: size)
                ?? Self.loadFromWorkspace(path: path, size: size)
            if let image {
                Self.saveToDisk(image, url: cacheURL)
            }
            await MainActor.run {
                guard let self else { return }
                self.loading.remove(path)
                guard let image else { return }
                guard self.memory[path] == nil else { return }
                self.memory[path] = image
                self.markRecent(path)
                self.evictIfNeeded()
                self.generation &+= 1
            }
        }
    }

    private func markRecent(_ key: String) {
        lru.removeAll { $0 == key }
        lru.append(key)
    }

    private func evictIfNeeded() {
        while memory.count > limit, let oldest = lru.first {
            lru.removeFirst()
            memory.removeValue(forKey: oldest)
        }
    }

    // ponytail: djb2 + lastPathComponent — 경로→파일명 매핑. 해시 충돌 확률 무시 가능,
    // 충돌 시 해당 아이콘만 캐시 미스(재로드). 정확성이 중요하면 SHA256으로 교체.
    private static func diskKey(path: String, size: CGFloat) -> String {
        var hash = 5381
        for byte in path.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        return "\(Int(size))_\(hash)_\((path as NSString).lastPathComponent).png"
    }

    private static func loadFromDisk(url: URL, size: CGFloat) -> NSImage? {
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return nil }
        let px = size * 2
        image.size = NSSize(width: px, height: px)
        return image
    }

    private static func loadFromWorkspace(path: String, size: CGFloat) -> NSImage? {
        let image = NSWorkspace.shared.icon(forFile: path)
        let px = size * 2
        image.size = NSSize(width: px, height: px)
        return image
    }

    private static func saveToDisk(_ image: NSImage, url: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url, options: .atomic)
    }
}

/// 옵셔널 아이콘을 렌더: 로드 전에는 옅은 글래스 placeholder를 보여준다.
struct IconImage: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .stroke(.white.opacity(0.05), lineWidth: 1)
                    )
            }
        }
        .frame(width: size, height: size)
    }
}
