import Foundation
import CoreServices
import SwiftUI

/// 監聽 ~/.project-tracker/，檔案一有變動就重新載入所有專案進度。
final class ProgressStore: ObservableObject {
    @Published private(set) var projects: [ProjectProgress] = []
    @Published private(set) var lastReload = Date()

    let homeURL: URL
    var projectsURL: URL { homeURL.appendingPathComponent("projects", isDirectory: true) }
    private var stream: FSEventStreamRef?
    private var pendingReload: DispatchWorkItem?

    init() {
        if let custom = ProcessInfo.processInfo.environment["PTRACK_HOME"], !custom.isEmpty {
            homeURL = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            homeURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".project-tracker", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        reload()
        startWatching()
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: - 統計

    var active: [ProjectProgress] {
        projects.filter { $0.status != .done && $0.status != .paused }
    }
    var paused: [ProjectProgress] { projects.filter { $0.status == .paused } }
    var done: [ProjectProgress] { projects.filter { $0.status == .done } }
    var attentionCount: Int { projects.reduce(0) { $0 + $1.attentionCount } }

    // MARK: - 載入

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: projectsURL, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        projects = files
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap(ProgressParser.parse(fileURL:))
            .sorted { $0.updated > $1.updated }
        lastReload = Date()
    }

    /// FSEvents 一次存檔常觸發多個事件，合併成一次重新載入。
    fileprivate func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func startWatching() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<ProgressStore>.fromOpaque(info).takeUnretainedValue().scheduleReload()
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [homeURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }
}
