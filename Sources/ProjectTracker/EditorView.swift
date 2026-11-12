import SwiftUI
import AppKit

/// 主視窗右側的編輯區：頁首（名稱、狀態、動作）＋各區段；寬度足夠時分成左右兩欄。
struct ProjectEditorView: View {
    @EnvironmentObject var store: ProgressStore
    let project: ProjectProgress

    var body: some View {
        VStack(spacing: 0) {
            EditorHeader(project: project)
            OnboardingBanner(project: project)
            Divider()
            GeometryReader { geo in
                ScrollView {
                    Group {
                        if geo.size.width >= 760 {
                            HStack(alignment: .top, spacing: 14) {
                                VStack(spacing: 14) {
                                    StateSection(project: project)
                                    NextStepsSection(project: project)
                                    BlockerSection(project: project)
                                }
                                VStack(spacing: 14) {
                                    TodoSection(project: project)
                                    HistorySection(project: project, limit: 10)
                                }
                            }
                        } else {
                            VStack(spacing: 14) {
                                StateSection(project: project)
                                NextStepsSection(project: project)
                                TodoSection(project: project)
                                BlockerSection(project: project)
                                HistorySection(project: project, limit: 10)
                            }
                        }
                    }
                    .padding(18)
                    Text("提示：雙擊項目可編輯；滑過項目會出現編輯與刪除按鈕；按 ＋ 新增，Esc 取消。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 16)
                }
            }
        }
    }
}

// MARK: - 頁首：名稱、狀態、資訊、動作

struct EditorHeader: View {
    @EnvironmentObject var store: ProgressStore
    let project: ProjectProgress
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var copied = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if editingName {
                    TextField("專案名稱", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                        .focused($nameFocused)
                        .onSubmit(saveName)
                        .onExitCommand { editingName = false }
                        .frame(maxWidth: 420)
                    Button("儲存", action: saveName)
                } else {
                    Text(project.name)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .onTapGesture(count: 2, perform: startRename)
                        .help("雙擊可改名")
                    Button(action: startRename) { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("改名")
                }
                StatusBadge(status: project.effectiveStatus)
                Spacer()
                Menu("變更狀態") {
                    StatusMenuItems(current: project.status) { store.setStatus(project, $0) }
                }
                .fixedSize()
                .help("把專案標為進行中／卡關／暫停／已完成")
            }

            HStack(spacing: 12) {
                Label("更新於 \(relativeTime(project.updated))", systemImage: "clock")
                    .lineLimit(1)
                    .fixedSize()
                if !project.agent.isEmpty {
                    Label(project.agent, systemImage: "cpu").lineLimit(1).fixedSize()
                }
                if !project.projectPath.isEmpty {
                    Button {
                        revealInFinder(project.projectPath)
                    } label: {
                        Label(project.projectPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                              systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.borderless)
                    .help("在 Finder 顯示專案資料夾")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    copyToPasteboard(Handoff.prompt(for: project))
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { copied = false } }
                } label: {
                    Label(copied ? "已複製" : "複製交接 prompt", systemImage: copied ? "checkmark" : "doc.on.clipboard")
                }
                .help("把目前進度組成一段文字，貼給新的 agent 接手")
                Button {
                    NSWorkspace.shared.open(project.fileURL)
                } label: {
                    Label("開啟進度檔", systemImage: "doc.text")
                }
                Spacer()
                Menu {
                    Button("用行前檔重新整理") { store.startOnboarding(project) }
                        .disabled(store.onboarding.contains(project.id) || project.projectPath.isEmpty)
                    Button("查看整理紀錄") { NSWorkspace.shared.open(store.logURL(for: project)) }
                        .disabled(!FileManager.default.fileExists(atPath: store.logURL(for: project).path))
                    Divider()
                    Button("在 Finder 顯示進度檔") { revealInFinder(project.fileURL.path) }
                    Divider()
                    Button("停止追蹤…", role: .destructive) { store.stopTracking(project) }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func startRename() {
        nameDraft = project.name
        editingName = true
        DispatchQueue.main.async { nameFocused = true }
    }

    private func saveName() {
        let name = nameDraft.trimmingCharacters(in: .whitespaces)
        editingName = false
        guard !name.isEmpty, name != project.name else { return }
        store.edit(project) { $0.set("project", name) }
    }
}

// MARK: - 目前狀態

struct StateSection: View {
    @EnvironmentObject var store: ProgressStore
    let project: ProjectProgress
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        SectionBox(kind: .state) {
            if !editing {
                Button {
                    draft = project.currentState
                    editing = true
                } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("編輯目前狀態")
            }
        } content: {
            if editing {
                VStack(alignment: .trailing, spacing: 6) {
                    TextField("這個專案做到哪裡了？", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...10)
                    HStack {
                        Button("取消") { editing = false }
                        Button("儲存") {
                            editing = false
                            let text = draft
                            store.edit(project) { $0.currentState = text }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .controlSize(.small)
                }
            } else if project.currentState.isEmpty {
                EmptyHint(text: "尚未填寫")
            } else {
                Text(project.currentState)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .onTapGesture(count: 2) {
                        draft = project.currentState
                        editing = true
                    }
            }
        }
    }
}

// MARK: - 下一步

struct NextStepsSection: View {
    @EnvironmentObject var store: ProgressStore
    let project: ProjectProgress
    @State private var adding = false

    var body: some View {
        SectionBox(kind: .next, count: project.nextSteps.count) {
            AddButton(help: "新增下一步") { adding = true }
        } content: {
            ForEach(Array(project.nextSteps.enumerated()), id: \.offset) { i, step in
                EditableRow(text: step, onSave: { new in
                    store.edit(project) { doc in
                        if let j = doc.nextSteps.resolvedIndex(i, expected: step) { doc.nextSteps[j] = new }
                    }
                }, onDelete: {
                    store.edit(project) { doc in
                        if let j = doc.nextSteps.resolvedIndex(i, expected: step) { doc.nextSteps.remove(at: j) }
                    }
                }) {
                    Text("\(i + 1).").font(.callout.monospacedDigit()).foregroundStyle(SectionStyle.tint(.next))
                }
            }
            if project.nextSteps.isEmpty && !adding { EmptyHint(text: "沒有下一步，按 ＋ 新增") }
            if adding {
                AddField(placeholder: "接手的人第一件要做的事…", isPresented: $adding) { text in
                    store.edit(project) { $0.nextSteps.append(text) }
                }
            }
        }
    }
}

// MARK: - 待辦

struct TodoSection: View {
    @EnvironmentObject var store: ProgressStore
    let project: ProjectProgress
    @State private var adding = false

    var body: some View {
        SectionBox(kind: .todo, count: project.totalCount) {
            HStack(spacing: 8) {
                if project.pendingCount > 0 {
                    Button("全部確認") { confirmAll() }
                        .controlSize(.small)
                        .help("把所有「待確認」標為已完成")
                }
                AddButton(help: "新增待辦") { adding = true }
            }
        } content: {
            if project.totalCount > 0 {
                HStack(spacing: 8) {
                    ProgressView(value: project.fraction).tint(SectionStyle.tint(.todo))
                    Text("\(project.doneCount)/\(project.totalCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            // 待確認放最上面，其次未完成，已完成放最後
            ForEach(ordered, id: \.offset) { i, todo in
                EditableRow(text: todo.text, dimmed: todo.state == .done, strikethrough: todo.state == .done,
                            onSave: { new in update(i, todo) { $0.text = new } },
                            onDelete: { remove(i, todo) }) {
                    toggle(i, todo)
                } extra: {
                    if todo.state == .pending {
                        HStack(spacing: 4) {
                            Button("確認") { update(i, todo) { $0.state = .done } }
                                .help("確認 agent 已完成這項")
                            Button("退回") { update(i, todo) { $0.state = .open } }
                                .help("還沒完成，改回未完成")
                        }
                        .controlSize(.mini)
                    }
                }
            }
            if project.todos.isEmpty && !adding { EmptyHint(text: "沒有待辦，按 ＋ 新增") }
            if adding {
                AddField(placeholder: "新增一項待辦…", isPresented: $adding) { text in
                    store.edit(project) { $0.todos.append(TodoItem(state: .open, text: text)) }
                }
            }
        }
    }

    private var ordered: [(offset: Int, element: TodoItem)] {
        let rank: [TodoState: Int] = [.pending: 0, .open: 1, .done: 2]
        return project.todos.enumerated().map { ($0.offset, $0.element) }
            .sorted { (rank[$0.1.state]!, $0.0) < (rank[$1.1.state]!, $1.0) }
            .map { (offset: $0.0, element: $0.1) }
    }

    @ViewBuilder private func toggle(_ i: Int, _ todo: TodoItem) -> some View {
        Button {
            update(i, todo) { $0.state = (todo.state == .done) ? .open : .done }
        } label: {
            switch todo.state {
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(SectionStyle.tint(.todo))
            case .pending:
                Image(systemName: "hourglass.circle.fill").foregroundStyle(SectionStyle.pending)
            case .open:
                Image(systemName: "circle").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .help(todo.state == .pending ? "agent 回報已完成，等你確認" : "切換完成狀態")
    }

    private func update(_ i: Int, _ todo: TodoItem, _ change: @escaping (inout TodoItem) -> Void) {
        store.edit(project) { doc in
            var list = doc.todos
            guard let j = list.resolvedIndex(i, expected: todo) else { return }
            change(&list[j])
            doc.todos = list
        }
    }

    private func remove(_ i: Int, _ todo: TodoItem) {
        store.edit(project) { doc in
            if let j = doc.todos.resolvedIndex(i, expected: todo) { doc.todos.remove(at: j) }
        }
    }

    private func confirmAll() {
        store.edit(project) { doc in
            doc.todos = doc.todos.map { t in
                var t = t
                if t.state == .pending { t.state = .done }
                return t
            }
        }
    }
}

// MARK: - 卡關／待決事項

struct BlockerSection: View {
    @EnvironmentObject var store: ProgressStore
    let project: ProjectProgress
    @State private var adding = false
    @State private var decidingIndex: Int?
    @State private var decision = ""
    @FocusState private var decisionFocused: Bool

    var body: some View {
        SectionBox(kind: .blockers, count: project.blockers.count) {
            AddButton(help: "新增卡關或待決事項") { adding = true }
        } content: {
            ForEach(Array(project.blockers.enumerated()), id: \.offset) { i, blocker in
                VStack(alignment: .leading, spacing: 4) {
                    EditableRow(text: blocker, onSave: { new in
                        store.edit(project) { doc in
                            if let j = doc.blockers.resolvedIndex(i, expected: blocker) { doc.blockers[j] = new }
                        }
                    }, onDelete: {
                        store.edit(project) { doc in
                            if let j = doc.blockers.resolvedIndex(i, expected: blocker) { doc.blockers.remove(at: j) }
                        }
                    }) {
                        Image(systemName: SectionStyle.icon(.blockers)).foregroundStyle(SectionStyle.tint(.blockers))
                    } extra: {
                        HStack(spacing: 4) {
                            Button("決定…") {
                                decision = ""
                                decidingIndex = i
                                DispatchQueue.main.async { decisionFocused = true }
                            }
                            .help("寫下你的決定，會交給下一個 agent")
                            Button("已解決") { resolve(i, blocker, decision: nil) }
                                .help("移除並記錄到歷程")
                        }
                        .controlSize(.mini)
                    }
                    if decidingIndex == i {
                        HStack(spacing: 6) {
                            TextField("你的決定（例如：用本機 MLX）", text: $decision, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .focused($decisionFocused)
                                .onSubmit { resolve(i, blocker, decision: decision) }
                                .onExitCommand { decidingIndex = nil }
                            Button("送出") { resolve(i, blocker, decision: decision) }
                                .controlSize(.small)
                                .disabled(decision.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .font(.callout)
                        .padding(.leading, 20)
                    }
                }
            }
            if project.blockers.isEmpty && !adding { EmptyHint(text: "目前沒有卡關，按 ＋ 新增") }
            if adding {
                AddField(placeholder: "需要你決定或卡住的事…", isPresented: $adding) { text in
                    store.edit(project) { $0.blockers.append(text) }
                }
            }
        }
    }

    /// 解決待決事項：從清單移除並寫入歷程；有決定時也放到「下一步」最前面，讓下一個 agent 看到。
    private func resolve(_ i: Int, _ blocker: String, decision: String?) {
        let d = decision?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if decision != nil && d.isEmpty { return }
        decidingIndex = nil
        store.edit(project) { doc in
            guard let j = doc.blockers.resolvedIndex(i, expected: blocker) else { return }
            doc.blockers.remove(at: j)
            if d.isEmpty {
                doc.appendHistory("（使用者）已解決：\(blocker)")
            } else {
                doc.nextSteps.insert("依使用者決定執行：\(d)（原問題：\(blocker)）", at: 0)
                doc.appendHistory("（使用者）決定「\(blocker)」→ \(d)")
            }
        }
    }
}

// MARK: - 歷程

struct HistorySection: View {
    let project: ProjectProgress
    var limit = 5
    @State private var showAll = false

    var body: some View {
        SectionBox(kind: .history, count: project.history.count) {
            if project.history.count > limit {
                Button(showAll ? "收合" : "顯示全部") { showAll.toggle() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        } content: {
            let items = Array(project.history.reversed())
            if items.isEmpty {
                EmptyHint(text: "還沒有歷程紀錄")
            } else {
                ForEach(Array((showAll ? items : Array(items.prefix(limit))).enumerated()), id: \.offset) { _, entry in
                    HistoryEntry(text: entry)
                }
            }
        }
    }
}

/// 歷程一行：把開頭的時間戳拆出來，用次要色顯示。
struct HistoryEntry: View {
    let text: String

    var body: some View {
        let parts = split(text)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(parts.time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(parts.message).font(.body).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func split(_ s: String) -> (time: String, message: String) {
        guard let r = s.range(of: #"^\d{4}-\d{2}-\d{2}( \d{2}:\d{2})?"#, options: .regularExpression) else {
            return ("", s)
        }
        let time = String(s[r]).replacingOccurrences(of: #"^\d{4}-"#, with: "", options: .regularExpression)
        return (time, s[r.upperBound...].trimmingCharacters(in: .whitespaces))
    }
}


// MARK: - 行前檔整理狀態

/// 整理中顯示提示；整理完成後顯示 Claude 的回報（可關閉）。
struct OnboardingBanner: View {
    @EnvironmentObject var store: ProgressStore
    let project: ProjectProgress

    var body: some View {
        if store.onboarding.contains(project.id) {
            banner(tint: .blue) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude 正在依行前檔整理既有進度…").font(.callout.weight(.semibold))
                    Text("會閱讀專案文件、git 紀錄、過去的對話與程式碼，通常需要 1～5 分鐘。完成前先不要編輯，以免內容被覆蓋。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        } else if let report = store.onboardingReports[project.id] {
            banner(tint: .green) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("已依行前檔整理完成，請檢查內容；⏳ 待確認的待辦與「卡關／待決事項」是 Claude 不確定、需要你確認的地方。")
                        .font(.callout.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(report).font(.caption).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                }
                Spacer()
                Button { store.onboardingReports[project.id] = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("關閉")
            }
        }
    }

    private func banner<Content: View>(tint: Color, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) { content() }
            .padding(12)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
    }
}
