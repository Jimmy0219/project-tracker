import Foundation
import CoreServices
import AppKit

/// 管理追蹤中的 PROGRESS.md：清單、即時監看、Claude 活動燈號與所有寫回動作。
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()

    @Published private(set) var projects: [ProjectProgress] = []
    @Published private(set) var missingPaths: [String] = []
    @Published var errorMessage: String?

    let homeURL: URL
    var trackedURL: URL { homeURL.appendingPathComponent("tracked.json") }
    var guideURL: URL { homeURL.appendingPathComponent("import-guide.md") }
    var defaultGuideURL: URL { homeURL.appendingPathComponent("templates/import-guide.default.md") }
    private let claudeProjectsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)

    private var trackedPaths: [String] = []
    private var stream: FSEventStreamRef?
    private var pendingReload: DispatchWorkItem?
    private var activityTimer: Timer?

    init() {
        if let custom = ProcessInfo.processInfo.environment["PTRACK_HOME"], !custom.isEmpty {
            homeURL = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            homeURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".project-tracker", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        loadTracked()
        reload()
        restartWatching()
        activityTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refreshActivity()
        }
    }

    // MARK: - 統計

    var active: [ProjectProgress] { projects.filter { $0.status == .inProgress } }
    var paused: [ProjectProgress] { projects.filter { $0.status == .paused } }
    var done: [ProjectProgress] { projects.filter { $0.status == .done } }
    var attentionCount: Int { projects.reduce(0) { $0 + $1.attentionCount } }
    var workingCount: Int { projects.filter(\.isWorking).count }

    func project(id: String) -> ProjectProgress? { projects.first { $0.id == id } }

    // MARK: - 追蹤清單

    private func loadTracked() {
        guard let data = try? Data(contentsOf: trackedURL),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return }
        trackedPaths = list
    }

    private func saveTracked() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? enc.encode(trackedPaths) { try? data.write(to: trackedURL, options: .atomic) }
    }

    /// 匯入拖進來的檔案或資料夾（資料夾會找裡面的 PROGRESS.md）。回傳第一個匯入專案的 id。
    @discardableResult
    func importItems(_ urls: [URL]) -> String? {
        var firstID: String?
        var problems: [String] = []
        for url in urls {
            var file = url.standardizedFileURL
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir), isDir.boolValue {
                file = file.appendingPathComponent("PROGRESS.md")
            }
            guard FileManager.default.fileExists(atPath: file.path) else {
                problems.append("找不到 \(file.path)，請先讓 Claude 依匯入說明建立 PROGRESS.md")
                continue
            }
            guard file.pathExtension.lowercased() == "md" else {
                problems.append("\(file.lastPathComponent) 不是 .md 檔")
                continue
            }
            if !trackedPaths.contains(file.path) { trackedPaths.append(file.path) }
            firstID = firstID ?? file.path
        }
        saveTracked()
        reload()
        restartWatching()
        if !problems.isEmpty { errorMessage = problems.joined(separator: "\n") }
        return firstID
    }

    @discardableResult
    func importInteractively() -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "選擇專案的 PROGRESS.md（或專案資料夾）"
        panel.prompt = "開始追蹤"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .folder]
        guard panel.runModal() == .OK else { return nil }
        return importItems(panel.urls)
    }

    /// 停止追蹤：只從清單移除，不會刪除專案裡的 PROGRESS.md。
    func untrack(_ project: ProjectProgress) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "停止追蹤「\(project.name)」？"
        alert.informativeText = "只會從 Project Tracker 的清單移除，專案裡的 PROGRESS.md 不會被刪除，之後可以再拖進來。"
        alert.addButton(withTitle: "停止追蹤")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        trackedPaths.removeAll { $0 == project.fileURL.path }
        saveTracked()
        reload()
        restartWatching()
    }

    func forgetMissing(_ path: String) {
        trackedPaths.removeAll { $0 == path }
        saveTracked()
        reload()
    }

    // MARK: - 編輯

    func edit(_ project: ProjectProgress, _ change: (inout ProgressDocument) -> Void) {
        do {
            try ProgressEditor.mutate(project.fileURL, change)
            reload()
        } catch {
            errorMessage = "無法寫入 PROGRESS.md：\(error.localizedDescription)"
        }
    }

    func setStatus(_ project: ProjectProgress, _ status: ProjectStatus) {
        edit(project) { $0.set("status", status.rawValue) }
    }

    // MARK: - 匯入說明

    func loadGuide() -> String { (try? String(contentsOf: guideURL, encoding: .utf8)) ?? "" }
    func defaultGuide() -> String? { try? String(contentsOf: defaultGuideURL, encoding: .utf8) }

    func saveGuide(_ text: String) {
        do { try text.write(to: guideURL, atomically: true, encoding: .utf8) }
        catch { errorMessage = "無法儲存匯入說明：\(error.localizedDescription)" }
    }

    // MARK: - 載入

    func reload() {
        var loaded: [ProjectProgress] = []
        var missing: [String] = []
        for path in trackedPaths {
            if var p = ProgressParser.parse(fileURL: URL(fileURLWithPath: path)) {
                p.activity = activity(for: p.projectURL)
                loaded.append(p)
            } else {
                missing.append(path)
            }
        }
        projects = loaded.sorted { lhs, rhs in
            if lhs.isWorking != rhs.isWorking { return lhs.isWorking }
            return lhs.updated > rhs.updated
        }
        missingPaths = missing
    }

    // MARK: - Claude 活動燈號

    /// Claude Code 把每個資料夾的對話存在 ~/.claude/projects/<路徑中非英數字元換成 ->/*.jsonl。
    /// 子資料夾開的 session 也算（名稱以專案路徑開頭）。
    private func activity(for projectURL: URL) -> Activity {
        let key = projectURL.path.replacingOccurrences(of: "[^A-Za-z0-9]", with: "-", options: .regularExpression)
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: claudeProjectsURL, includingPropertiesForKeys: nil) else {
            return .unknown
        }
        var latest: Date?
        for dir in dirs where dir.lastPathComponent == key || dir.lastPathComponent.hasPrefix(key + "-") {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for f in files where f.pathExtension == "jsonl" {
                if let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   d > (latest ?? .distantPast) {
                    latest = d
                }
            }
        }
        guard let latest else { return .unknown }
        return Date().timeIntervalSince(latest) < 120 ? .working : .idle(latest)
    }

    private func refreshActivity() {
        var changed = false
        var updated = projects
        for i in updated.indices {
            let a = activity(for: updated[i].projectURL)
            if a != updated[i].activity { updated[i].activity = a; changed = true }
        }
        if changed { projects = updated }
    }

    // MARK: - 即時監看 PROGRESS.md

    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// 監看每個追蹤檔所在的資料夾（檔案被原子寫入時會換 inode，所以監看資料夾）。
    private func restartWatching() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        let dirs = Array(Set(trackedPaths.map { ($0 as NSString).deletingLastPathComponent }))
        guard !dirs.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let store = Unmanaged<ProgressStore>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            // 只在 .md 檔變動時重新載入，避免專案裡其他檔案頻繁觸發
            if list.contains(where: { $0.lowercased().hasSuffix(".md") }) || count == 0 {
                store.scheduleReload()
            }
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, dirs as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags)
        else { return }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        stream = s
    }
}
