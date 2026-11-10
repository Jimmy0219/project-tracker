import SwiftUI
import AppKit
import ServiceManagement

// MARK: - 主畫面

struct ContentView: View {
    @EnvironmentObject var store: ProgressStore
    @State private var showDone = false
    @State private var showPaused = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.projects.isEmpty {
                EmptyStateView(folder: store.projectsURL)
            } else {
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(store.active) { ProjectCard(project: $0, now: context.date) }
                            if !store.paused.isEmpty {
                                SectionToggle(title: "暫停", count: store.paused.count, isOn: $showPaused)
                                if showPaused {
                                    ForEach(store.paused) { ProjectCard(project: $0, now: context.date) }
                                }
                            }
                            if !store.done.isEmpty {
                                SectionToggle(title: "已完成", count: store.done.count, isOn: $showDone)
                                if showDone {
                                    ForEach(store.done) { ProjectCard(project: $0, now: context.date) }
                                }
                            }
                        }
                        .padding(10)
                    }
                }
                .frame(maxHeight: 560)
            }
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("專案進度").font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                NSWorkspace.shared.open(store.projectsURL)
            } label: { Image(systemName: "folder") }
            .buttonStyle(.borderless)
            .help("在 Finder 開啟進度檔資料夾")
            SettingsMenu()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var summary: String {
        var parts = ["\(store.active.count) 個進行中"]
        let blocked = store.active.filter { $0.effectiveStatus == .blocked }.count
        if blocked > 0 { parts.append("\(blocked) 個卡關") }
        if store.attentionCount > 0 { parts.append("\(store.attentionCount) 件待決") }
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
                        NSSound.beep()
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
    let folder: URL

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.largeTitle).foregroundStyle(.tertiary)
            Text("還沒有追蹤中的專案").font(.callout.weight(.medium))
            Text("在專案裡用 Claude Code 工作，收工時進度會自動寫進\n\(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 專案卡片

struct ProjectCard: View {
    let project: ProjectProgress
    let now: Date
    @State private var expanded = false
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleRow
            if project.totalCount > 0 { progressRow }
            if let next = project.nextSteps.first {
                Label {
                    Text(next).lineLimit(expanded ? nil : 2)
                } icon: {
                    Image(systemName: "arrow.right.circle").foregroundStyle(.blue)
                }
                .font(.callout)
            }
            blockerList
            if expanded { details }
            actionRow
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(project.effectiveStatus == .blocked ? Color.orange.opacity(0.5) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            StatusBadge(status: project.effectiveStatus)
            Text(project.name).font(.body.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 4)
            Text(relative(project.updated))
                .font(.caption)
                .foregroundStyle(isStale ? .orange : .secondary)
                .help(project.updated.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            ProgressView(value: project.fraction)
                .tint(project.status == .done ? .green : .accentColor)
            Text("\(project.doneCount)/\(project.totalCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var blockerList: some View {
        let shown = expanded ? project.blockers : Array(project.blockers.prefix(2))
        ForEach(Array(shown.enumerated()), id: \.offset) { _, b in
            Label {
                Text(b).lineLimit(expanded ? nil : 2)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.callout)
        }
        if !expanded && project.blockers.count > 2 {
            Text("還有 \(project.blockers.count - 2) 件待決…").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !project.currentState.isEmpty {
                DetailBlock(title: "目前狀態") { Text(project.currentState) }
            }
            if project.nextSteps.count > 1 {
                DetailBlock(title: "下一步") {
                    ForEach(Array(project.nextSteps.enumerated()), id: \.offset) { _, s in Text("• \(s)") }
                }
            }
            if !project.openTodos.isEmpty {
                DetailBlock(title: "未完成待辦") {
                    ForEach(Array(project.openTodos.enumerated()), id: \.offset) { _, t in
                        Label(t.text, systemImage: "circle")
                    }
                }
            }
            if !project.history.isEmpty {
                DetailBlock(title: "最近歷程") {
                    ForEach(Array(project.history.suffix(3).reversed().enumerated()), id: \.offset) { _, h in
                        Text(h).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 4) {
                if !project.agent.isEmpty { Text(project.agent) }
                if !project.projectPath.isEmpty {
                    Text("·")
                    Text(project.projectPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .truncationMode(.middle)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .font(.callout)
        .padding(.top, 2)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Handoff.prompt(for: project), forType: .string)
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { copied = false } }
            } label: {
                Label(copied ? "已複製" : "複製交接 prompt",
                      systemImage: copied ? "checkmark" : "doc.on.clipboard")
            }
            Button {
                NSWorkspace.shared.open(project.fileURL)
            } label: {
                Label("開啟進度檔", systemImage: "doc.text")
            }
            Spacer()
            Image(systemName: "chevron.down")
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .padding(.top, 2)
    }

    private var isStale: Bool {
        project.status == .inProgress && now.timeIntervalSince(project.updated) > 7 * 86_400
    }

    private func relative(_ date: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "剛剛" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh-Hant-TW")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: now)
    }
}

struct DetailBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusBadge: View {
    let status: ProjectStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .inProgress: return .blue
        case .blocked: return .orange
        case .paused: return .gray
        case .done: return .green
        case .unknown: return .secondary
        }
    }
}
