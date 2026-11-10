import SwiftUI
import AppKit
import ServiceManagement

// MARK: - 根畫面：清單頁 ⇄ 詳細頁

struct ContentView: View {
    @EnvironmentObject var store: ProgressStore
    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 0) {
            if let id = selectedID, let project = store.project(id: id) {
                ProjectDetailView(project: project) { selectedID = nil }
            } else {
                ProjectListView { selectedID = $0 }
            }
            if let message = store.errorMessage {
                ErrorBanner(message: message) { store.errorMessage = nil }
            }
        }
        .frame(width: 400)
        .onChange(of: store.projects.map(\.id)) { _, ids in
            if let id = selectedID, !ids.contains(id) { selectedID = nil }
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            Text(message).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.red.opacity(0.1))
    }
}

// MARK: - 清單頁

struct ProjectListView: View {
    @EnvironmentObject var store: ProgressStore
    let onSelect: (String) -> Void
    @State private var showDone = false
    @State private var showPaused = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.projects.isEmpty {
                EmptyStateView { add() }
            } else {
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(store.active) { row($0, now: context.date) }
                            if !store.paused.isEmpty {
                                SectionToggle(title: "暫停", count: store.paused.count, isOn: $showPaused)
                                if showPaused { ForEach(store.paused) { row($0, now: context.date) } }
                            }
                            if !store.done.isEmpty {
                                SectionToggle(title: "已完成", count: store.done.count, isOn: $showDone)
                                if showDone { ForEach(store.done) { row($0, now: context.date) } }
                            }
                        }
                        .padding(10)
                    }
                }
                .frame(maxHeight: 560)
            }
        }
    }

    private func row(_ p: ProjectProgress, now: Date) -> some View {
        ProjectRow(project: p, now: now) { onSelect(p.id) }
    }

    private func add() {
        if let id = store.addProjectInteractively() { onSelect(id) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("專案進度").font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: add) { Image(systemName: "plus") }
                .help("新增要追蹤的專案")
            Button { NSWorkspace.shared.open(store.projectsURL) } label: { Image(systemName: "folder") }
                .help("在 Finder 開啟進度檔資料夾")
            SettingsMenu()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var summary: String {
        var parts = ["\(store.active.count) 個進行中"]
        let blockers = store.active.reduce(0) { $0 + $1.blockers.count }
        let pending = store.active.reduce(0) { $0 + $1.pendingCount }
        if blockers > 0 { parts.append("\(blockers) 件待決") }
        if pending > 0 { parts.append("\(pending) 件待確認") }
        if !store.done.isEmpty { parts.append("\(store.done.count) 個已完成") }
        return parts.joined(separator: " · ")
    }
}

struct SectionToggle: View {
    let title: String
    let count: Int
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isOn ? 90 : 0))
                    .font(.caption2.weight(.semibold))
                Text("\(title)（\(count)）").font(.caption.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
}

/// 清單中的精簡卡片：只放摘要，點擊進入分段的詳細頁。
struct ProjectRow: View {
    @EnvironmentObject var store: ProgressStore
    let project: ProjectProgress
    let now: Date
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                StatusBadge(status: project.effectiveStatus)
                Text(project.name).font(.body.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(relativeTime(project.updated, now: now))
                    .font(.caption)
                    .foregroundStyle(isStale ? .orange : .secondary)
                    .help(isStale ? "超過 7 天沒有更新" : project.updated.formatted(date: .abbreviated, time: .shortened))
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            if project.totalCount > 0 {
                HStack(spacing: 8) {
                    ProgressView(value: project.fraction)
                        .tint(project.status == .done ? .green : .accentColor)
                    Text("\(project.doneCount)/\(project.totalCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let next = project.nextSteps.first {
                Label {
                    Text(next).lineLimit(1)
                } icon: {
                    Image(systemName: SectionStyle.icon(.next)).foregroundStyle(SectionStyle.tint(.next))
                }
                .font(.callout)
            }
            if !project.blockers.isEmpty || project.pendingCount > 0 {
                HStack(spacing: 6) {
                    if !project.blockers.isEmpty {
                        CountChip(icon: SectionStyle.icon(.blockers), text: "\(project.blockers.count) 件待決",
                                  tint: SectionStyle.tint(.blockers))
                    }
                    if project.pendingCount > 0 {
                        CountChip(icon: "hourglass", text: "\(project.pendingCount) 件待確認", tint: SectionStyle.pending)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.09 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(project.attentionCount > 0 ? Color.orange.opacity(0.45) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onOpen)
        .contextMenu {
            Button("打開詳細內容", action: onOpen)
            Menu("改狀態") {
                StatusMenuItems(current: project.status) { store.setStatus(project, $0) }
            }
            Divider()
            Button("複製交接 prompt") { copyToPasteboard(Handoff.prompt(for: project)) }
            Button("開啟進度檔") { NSWorkspace.shared.open(project.fileURL) }
            if !project.projectPath.isEmpty {
                Button("在 Finder 顯示專案資料夾") { revealInFinder(project.projectPath) }
            }
            Divider()
            Button("停止追蹤…", role: .destructive) { store.stopTracking(project) }
        }
    }

    private var isStale: Bool {
        project.status == .inProgress && now.timeIntervalSince(project.updated) > 7 * 86_400
    }

    private var accessibilitySummary: String {
        var parts = [project.name, project.effectiveStatus.label, "更新於\(relativeTime(project.updated, now: now))"]
        if project.totalCount > 0 { parts.append("待辦 \(project.doneCount)/\(project.totalCount)") }
        if !project.blockers.isEmpty { parts.append("\(project.blockers.count) 件待決") }
        if project.pendingCount > 0 { parts.append("\(project.pendingCount) 件待確認") }
        return parts.joined(separator: "，")
    }
}

struct SettingsMenu: View {
    @EnvironmentObject var store: ProgressStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Menu {
            Toggle("登入時啟動", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    do {
                        if newValue { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
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
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.largeTitle).foregroundStyle(.tertiary)
            Text("還沒有追蹤中的專案").font(.callout.weight(.medium))
            Text("用 Claude Code 在專案裡工作，收工時會自動出現在這裡；\n也可以直接新增。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("新增專案…", action: onAdd).controlSize(.small)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
