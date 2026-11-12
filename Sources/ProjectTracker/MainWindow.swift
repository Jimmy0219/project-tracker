import SwiftUI
import AppKit

/// 主視窗：左側專案清單，右側寬版編輯區。
struct MainWindowView: View {
    @EnvironmentObject var store: ProgressStore
    @EnvironmentObject var model: MainWindowModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 260)
            Divider()
            Group {
                if model.selectedID == OnboardingBriefView.selectionID {
                    OnboardingBriefView()
                } else if let id = model.selectedID, let project = store.project(id: id) {
                    ProjectEditorView(project: project)
                        .id(project.id)  // 換專案時重設各區段的編輯狀態
                } else {
                    NoSelectionView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 480)
        .overlay(alignment: .bottom) {
            if let message = store.errorMessage {
                ErrorBanner(message: message) { store.errorMessage = nil }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
        .onChange(of: store.projects.map(\.id)) { _, ids in
            if let id = model.selectedID, id != OnboardingBriefView.selectionID, !ids.contains(id) {
                model.selectedID = ids.first
            }
        }
    }
}

// MARK: - 側欄

struct SidebarView: View {
    @EnvironmentObject var store: ProgressStore
    @EnvironmentObject var model: MainWindowModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("專案").font(.headline)
                Spacer()
                Button {
                    if let id = store.addProjectInteractively() { model.selectedID = id }
                } label: {
                    Label("新增專案", systemImage: "plus")
                }
                .help("選擇資料夾，開始追蹤一個專案")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜尋專案", text: $model.search).textFieldStyle(.plain)
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            List(selection: $model.selectedID) {
                group("進行中", filtered(store.active))
                group("暫停", filtered(store.paused))
                group("已完成", filtered(store.done))
            }
            .listStyle(.sidebar)
            .overlay {
                if store.projects.isEmpty {
                    VStack(spacing: 8) {
                        Text("還沒有追蹤中的專案").foregroundStyle(.secondary)
                        Button("新增專案…") {
                            if let id = store.addProjectInteractively() { model.selectedID = id }
                        }
                    }
                }
            }

            Divider()
            Button {
                model.selectedID = OnboardingBriefView.selectionID
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("行前檔").font(.body.weight(.medium))
                        Text("新專案匯入時 Claude 依此整理進度").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .background(model.selectedID == OnboardingBriefView.selectionID ? Color.accentColor.opacity(0.18) : .clear)
            }
            .buttonStyle(.plain)
            .help("編輯匯入新專案時給 Claude 的指引")
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [ProjectProgress]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { p in
                    SidebarRow(project: p)
                        .tag(p.id as String?)
                        .contextMenu { ProjectMenuItems(project: p) }
                }
            }
        }
    }

    private func filtered(_ items: [ProjectProgress]) -> [ProjectProgress] {
        let q = model.search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.projectPath.localizedCaseInsensitiveContains(q) }
    }
}

struct SidebarRow: View {
    @EnvironmentObject var store: ProgressStore
    let project: ProjectProgress

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if store.onboarding.contains(project.id) {
                ProgressView().controlSize(.mini).frame(width: 8, height: 8).padding(.top, 5)
            } else {
                Circle()
                    .fill(StatusBadge.color(project.effectiveStatus))
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    if store.onboarding.contains(project.id) { Text("整理中…").foregroundStyle(.blue) }
                    if project.totalCount > 0 { Text("\(project.doneCount)/\(project.totalCount)") }
                    if !project.blockers.isEmpty {
                        Label("\(project.blockers.count)", systemImage: SectionStyle.icon(.blockers))
                            .foregroundStyle(SectionStyle.tint(.blockers))
                    }
                    if project.pendingCount > 0 {
                        Label("\(project.pendingCount)", systemImage: "hourglass")
                            .foregroundStyle(SectionStyle.pending)
                    }
                    Text(relativeTime(project.updated))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 3)
    }
}

struct NoSelectionView: View {
    @EnvironmentObject var store: ProgressStore
    @EnvironmentObject var model: MainWindowModel

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.left").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("從左側選一個專案開始編輯").foregroundStyle(.secondary)
            Button("新增專案…") {
                if let id = store.addProjectInteractively() { model.selectedID = id }
            }
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
        .background(.regularMaterial)
        .background(Color.red.opacity(0.1))
    }
}
