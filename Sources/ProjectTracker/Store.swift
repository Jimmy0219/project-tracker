import Foundation
import CoreServices
import AppKit

/// 監聽 ~/.project-tracker/，檔案一有變動就重新載入；也負責所有寫回進度檔的動作。
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()

    @Published private(set) var projects: [ProjectProgress] = []
    @Published var errorMessage: String?
    /// 正在依行前檔整理中的專案（id = 進度檔路徑）
    @Published private(set) var onboarding: Set<String> = []
    /// 最近一次整理完成後 Claude 的回報
    @Published var onboardingReports: [String: String] = [:]

    let homeURL: URL
    var projectsURL: URL { homeURL.appendingPathComponent("projects", isDirectory: true) }
    var ignoreURL: URL { homeURL.appendingPathComponent("ignore") }
    var ptrackURL: URL { homeURL.appendingPathComponent("bin/ptrack") }
    var briefURL: URL { homeURL.appendingPathComponent("onboarding.md") }
    var defaultBriefURL: URL { homeURL.appendingPathComponent("templates/onboarding.default.md") }

    func logURL(for project: ProjectProgress) -> URL {
        homeURL.appendingPathComponent("logs/\(project.fileURL.deletingPathExtension().lastPathComponent).log")
    }
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

    var active: [ProjectProgress] { projects.filter(\.isActive) }
    var paused: [ProjectProgress] { projects.filter { $0.status == .paused } }
    var done: [ProjectProgress] { projects.filter { $0.status == .done } }
    var attentionCount: Int { projects.reduce(0) { $0 + $1.attentionCount } }

    func project(id: String) -> ProjectProgress? { projects.first { $0.id == id } }

    // MARK: - 編輯

    /// 修改單一專案的進度檔。change 拿到的是剛從磁碟讀出的最新內容。
    func edit(_ project: ProjectProgress, _ change: (inout ProgressDocument) -> Void) {
        do {
            try ProgressEditor.mutate(project.fileURL, change)
            reload()
        } catch {
            errorMessage = "無法寫入進度檔：\(error.localizedDescription)"
        }
    }

    func setStatus(_ project: ProjectProgress, _ status: ProjectStatus) {
        edit(project) { $0.set("status", status.rawValue) }
    }

    /// 選資料夾加入追蹤。成功時回傳該專案的 id（進度檔路徑）。
    @discardableResult
    func addProjectInteractively() -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "選擇要追蹤的專案資料夾"
        panel.prompt = "開始追蹤"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        guard panel.runModal() == .OK, let folder = panel.url else { return nil }
        return addProject(folder: folder)
    }

    @discardableResult
    func addProject(folder: URL) -> String? {
        guard FileManager.default.isExecutableFile(atPath: ptrackURL.path) else {
            errorMessage = "找不到 ptrack（\(ptrackURL.path)），請先執行 scripts/install.sh"
            return nil
        }
        do {
            let root = try runPtrack(["root", folder.path])
            removeFromIgnore([folder.path, root])
            let existing = try runPtrack(["file", folder.path])
            let isNew = !FileManager.default.fileExists(atPath: existing)
            let file = try runPtrack(["init", folder.path])
            reload()
            let url = URL(fileURLWithPath: file).standardizedFileURL
            guard let project = projects.first(where: { $0.fileURL.standardizedFileURL == url }) else { return file }
            // 新匯入的專案：自動請 Claude 依行前檔整理既有進度
            if isNew { startOnboarding(project) }
            return project.id
        } catch {
            errorMessage = "新增專案失敗：\(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - 行前檔匯入

    /// 在背景執行 `ptrack onboard`：Claude 讀行前檔、分析專案，寫入進度檔。
    func startOnboarding(_ project: ProjectProgress) {
        guard !onboarding.contains(project.id) else { return }
        let path = project.projectPath.isEmpty ? nil : project.projectPath
        guard let path else {
            errorMessage = "這個進度檔沒有記錄專案路徑，無法自動整理"
            return
        }
        onboarding.insert(project.id)
        onboardingReports[project.id] = nil
        let id = project.id, name = project.name, log = logURL(for: project)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Result { try runPtrack(["onboard", path]) }
            DispatchQueue.main.async { [self] in
                onboarding.remove(id)
                reload()
                switch result {
                case .success(let report):
                    onboardingReports[id] = report.isEmpty ? "整理完成" : report
                case .failure(let error):
                    let msg = error.localizedDescription
                    if msg.contains("401") || msg.localizedCaseInsensitiveContains("authenticate") {
                        errorMessage = "「\(name)」整理失敗：Claude CLI 登入已過期，請在終端機執行 claude auth login 後再按「用行前檔重新整理」。"
                    } else if msg.contains("找不到 claude") {
                        errorMessage = "「\(name)」整理失敗：找不到 Claude Code（claude 指令）。"
                    } else {
                        errorMessage = "「\(name)」整理失敗，詳細紀錄：\(log.path)"
                    }
                }
            }
        }
    }

    func loadBrief() -> String {
        (try? String(contentsOf: briefURL, encoding: .utf8)) ?? ""
    }

    func saveBrief(_ text: String) {
        do {
            try text.write(to: briefURL, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "無法儲存行前檔：\(error.localizedDescription)"
        }
    }

    func defaultBrief() -> String? {
        try? String(contentsOf: defaultBriefURL, encoding: .utf8)
    }

    /// 停止追蹤：進度檔移到垃圾桶（可復原），並把專案路徑加入忽略清單，避免 hook 又要求建立。
    func stopTracking(_ project: ProjectProgress) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "停止追蹤「\(project.name)」？"
        alert.informativeText = "進度檔會移到垃圾桶（可以從垃圾桶救回），這個資料夾也會加入忽略清單，之後 Claude Code 不會再要求為它更新進度。日後可用「新增專案」重新追蹤。"
        alert.addButton(withTitle: "停止追蹤")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: project.fileURL, resultingItemURL: nil)
            if !project.projectPath.isEmpty { appendToIgnore(project.projectPath) }
            reload()
        } catch {
            errorMessage = "無法移除進度檔：\(error.localizedDescription)"
        }
    }

    // MARK: - ptrack／忽略清單

    private func runPtrack(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = ptrackURL
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PTRACK_HOME"] = homeURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(home)/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        // 先在背景讀 stderr、前景讀 stdout，避免輸出塞滿管線時互相卡住
        var errData = Data()
        let errReader = DispatchQueue(label: "ptrack.stderr")
        let group = DispatchGroup()
        group.enter()
        errReader.async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            let stderr = String(data: errData, encoding: .utf8) ?? ""
            let detail = [stderr, stdout].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: "\n")
            throw NSError(domain: "ptrack", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: detail.isEmpty ? "ptrack 執行失敗" : detail])
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ignoreLines() -> [String] {
        ((try? String(contentsOf: ignoreURL, encoding: .utf8)) ?? "").components(separatedBy: "\n")
    }

    private func appendToIgnore(_ path: String) {
        var lines = ignoreLines().filter { !$0.isEmpty }
        guard !lines.contains(path) else { return }
        lines.append(path)
        try? (lines.joined(separator: "\n") + "\n").write(to: ignoreURL, atomically: true, encoding: .utf8)
    }

    private func removeFromIgnore(_ paths: [String]) {
        let lines = ignoreLines()
        let kept = lines.filter { !paths.contains($0.trimmingCharacters(in: .whitespaces)) }
        guard kept.count != lines.count else { return }
        try? kept.joined(separator: "\n").write(to: ignoreURL, atomically: true, encoding: .utf8)
    }

    // MARK: - 載入與監聽

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: projectsURL, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        projects = files
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap(ProgressParser.parse(fileURL:))
            .sorted { $0.updated > $1.updated }
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
