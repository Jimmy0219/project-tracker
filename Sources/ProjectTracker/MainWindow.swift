import SwiftUI
import AppKit

/// 主視窗：左側專案清單（可拖入 PROGRESS.md），右側編輯區。
struct MainWindowView: View {
    @EnvironmentObject var store: ProgressStore
    @EnvironmentObject var model: MainWindowModel
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView().frame(width: 260)
            Divider()
            Group {
                if model.selectedID == ImportGuideView.selectionID {
                    ImportGuideView()
                } else if let id = model.selectedID, let project = store.project(id: id) {
                    ProjectEditorView(project: project).id(project.id)
                } else {
                    NoSelectionView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 480)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.08))
                    .overlay(Label("放開以開始追蹤這個 PROGRESS.md", systemImage: "tray.and.arrow.down").font(.title3))
                    .padding(8)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadFileURLs(providers) { urls in
                if let id = store.importItems(urls) { model.selectedID = id }
            }
            return true
        }
        .overlay(alignment: .bottom) {
            if let message = store.errorMessage {
                ErrorBanner(message: message) { store.errorMessage = nil }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
        .onChange(of: store.projects.map(\.id)) { _, ids in
            if let id = model.selectedID, id != ImportGuideView.selectionID, !ids.contains(id) {
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
                    if let id = store.importInteractively() { model.selectedID = id }
                } label: {
                    Label("匯入", systemImage: "plus")
                }
                .help("選擇專案的 PROGRESS.md（也可以直接拖進視窗）")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜尋專案", text: $model.search).textFieldStyle(.plain)
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            List(selection: $model.selectedID) {
                group("進行中", filtered(store.active))
                group("暫停", filtered(store.paused))
                group("完成", filtered(store.done))
                if !store.missingPaths.isEmpty {
                    Section("找不到檔案") {
                        ForEach(store.missingPaths, id: \.self) { path in
                            HStack {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                                Text((path as NSString).deletingLastPathComponent.components(separatedBy: "/").last ?? path)
                                    .lineLimit(1)
                                Spacer()
                                Button("移除") { store.forgetMissing(path) }.controlSize(.small)
                            }
                            .help(path)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if store.projects.isEmpty && store.missingPaths.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down").font(.title).foregroundStyle(.tertiary)
                        Text("把 PROGRESS.md 拖進來").foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
            Button {
                model.selectedID = ImportGuideView.selectionID
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("匯入說明").font(.body.weight(.medium))
                        Text("丟給 Claude，讓它建立 PROGRESS.md").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .background(model.selectedID == ImportGuideView.selectionID ? Color.accentColor.opacity(0.18) : .clear)
            }
            .buttonStyle(.plain)
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
        return items.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.fileURL.path.localizedCaseInsensitiveContains(q) }
    }
}

struct SidebarRow: View {
    let project: ProjectProgress

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(project.isWorking ? Color.green : StatusBadge.color(project.status).opacity(0.6))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    if project.isWorking { Text("工作中").foregroundStyle(.green) }
                    if !project.tasks.isEmpty { Text("\(project.doneCount)/\(project.tasks.count)") }
                    if project.attentionCount > 0 {
                        Label("\(project.decisions.count)", systemImage: SectionStyle.icon(.decisions))
                            .foregroundStyle(SectionStyle.tint(.decisions))
                    }
                    if !project.isWorking { Text(relativeTime(project.updated)) }
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
    @EnvironmentObject var model: MainWindowModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("把專案的 PROGRESS.md 拖進這個視窗開始追蹤").font(.title3)
            Text("還沒有 PROGRESS.md？先把「匯入說明」丟給該專案的 Claude Code。")
                .foregroundStyle(.secondary)
            Button("查看匯入說明") { model.selectedID = ImportGuideView.selectionID }
                .buttonStyle(.borderedProminent)
        }
        .padding()
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
