import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - 選單列面板：一眼看懂的預覽，點專案在主視窗編輯

struct MenuPreviewView: View {
    @EnvironmentObject var store: ProgressStore
    @State private var showOthers = false
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.projects.isEmpty {
                EmptyStateView()
            } else {
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(store.active) { PreviewRow(project: $0, now: context.date) }
                            let others = store.paused + store.done
                            if !others.isEmpty {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) { showOthers.toggle() }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.right")
                                            .rotationEffect(.degrees(showOthers ? 90 : 0))
                                            .font(.caption2.weight(.semibold))
                                        Text("暫停／完成（\(others.count)）").font(.caption.weight(.semibold))
                                        Spacer()
                                    }
                                    .foregroundStyle(.secondary)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                                if showOthers { ForEach(others) { PreviewRow(project: $0, now: context.date) } }
                            }
                        }
                        .padding(10)
                    }
                }
                .frame(maxHeight: 520)
            }
            Divider()
            Button {
                MainWindowController.shared.show()
            } label: {
                Label("打開主視窗", systemImage: "macwindow").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08))
                    .overlay(Text("放開以開始追蹤").font(.headline))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadFileURLs(providers) { urls in
                if let id = store.importItems(urls) { MainWindowController.shared.show(selecting: id) }
            }
            return true
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("專案進度").font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            SettingsMenu()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var summary: String {
        var parts = ["\(store.active.count) 個進行中"]
        if store.workingCount > 0 { parts.append("\(store.workingCount) 個 Claude 工作中") }
        if store.attentionCount > 0 { parts.append("\(store.attentionCount) 件等你決定") }
        return parts.joined(separator: " · ")
    }
}

/// 預覽卡片：名稱、活動燈號、進度、下一步、等你決定。
struct PreviewRow: View {
    let project: ProjectProgress
    let now: Date
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(project.name).font(.body.weight(.semibold)).lineLimit(1)
                if project.status != .inProgress { StatusBadge(status: project.status) }
                Spacer(minLength: 4)
                if project.isWorking {
                    ActivityBadge(activity: project.activity)
                } else {
                    Text(relativeTime(project.updated, now: now)).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !project.tasks.isEmpty {
                HStack(spacing: 8) {
                    ProgressView(value: project.fraction).tint(project.status == .done ? .green : .accentColor)
                    Text("\(project.doneCount)/\(project.tasks.count)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if let next = project.nextTask {
                Label {
                    Text(next).lineLimit(1)
                } icon: {
                    Image(systemName: "arrow.right.circle.fill").foregroundStyle(SectionStyle.tint(.tasks))
                }
                .font(.callout)
            }
            if project.attentionCount > 0 {
                CountChip(icon: SectionStyle.icon(.decisions), text: "\(project.decisions.count) 件等你決定",
                          tint: SectionStyle.tint(.decisions))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.09 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(project.isWorking ? Color.green.opacity(0.5)
                          : project.attentionCount > 0 ? Color.orange.opacity(0.45) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .help("點擊在主視窗編輯")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, open)
        .contextMenu { ProjectMenuItems(project: project) }
    }

    private func open() { MainWindowController.shared.show(selecting: project.id) }

    private var accessibilitySummary: String {
        var parts = [project.name]
        if project.isWorking { parts.append("Claude 工作中") }
        if !project.tasks.isEmpty { parts.append("任務 \(project.doneCount)/\(project.tasks.count)") }
        if let n = project.nextTask { parts.append("下一步 \(n)") }
        if project.attentionCount > 0 { parts.append("\(project.decisions.count) 件等你決定") }
        return parts.joined(separator: "，")
    }
}

/// 專案右鍵選單（選單列與主視窗側欄共用）。
struct ProjectMenuItems: View {
    @EnvironmentObject var store: ProgressStore
    let project: ProjectProgress

    var body: some View {
        Button("在主視窗編輯") { MainWindowController.shared.show(selecting: project.id) }
        Menu("改狀態") {
            StatusMenuItems(current: project.status) { store.setStatus(project, $0) }
        }
        Divider()
        Button("開啟 PROGRESS.md") { NSWorkspace.shared.open(project.fileURL) }
        Button("在 Finder 顯示專案") { revealInFinder(project.fileURL) }
        Divider()
        Button("停止追蹤…") { store.untrack(project) }
    }
}

struct SettingsMenu: View {
    @EnvironmentObject var store: ProgressStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Menu {
            Button("打開主視窗") { MainWindowController.shared.show() }
            Button("匯入 PROGRESS.md…") {
                if let id = store.importInteractively() { MainWindowController.shared.show(selecting: id) }
            }
            Button("匯入說明（給 Claude 的 md）") { MainWindowController.shared.show(selecting: ImportGuideView.selectionID) }
            Divider()
            Toggle("登入時啟動", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    do {
                        if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        store.errorMessage = "無法變更登入時啟動：\(error.localizedDescription)"
                    }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            ))
            Button("重新整理") { store.reload() }
            Divider()
            Button("結束 Project Tracker") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down").font(.largeTitle).foregroundStyle(.tertiary)
            Text("還沒有追蹤中的專案").font(.callout.weight(.medium))
            Text("把專案的 PROGRESS.md 拖到這裡；\n還沒有的話，先看「匯入說明」。")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("匯入說明") { MainWindowController.shared.show(selecting: ImportGuideView.selectionID) }
                .controlSize(.small)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// 從拖放的項目取出檔案 URL。
func loadFileURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    var urls: [URL] = []
    let lock = NSLock()
    let group = DispatchGroup()
    for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            if let url { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) { completion(urls) }
}
