import SwiftUI
import AppKit

/// 主視窗右側的編輯區：頁首＋目標／現在＋任務＋等你決定＋紀錄。
struct ProjectEditorView: View {
    let project: ProjectProgress

    var body: some View {
        VStack(spacing: 0) {
            EditorHeader(project: project)
            Divider()
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            OneLineSection(project: project, kind: .goal, placeholder: "這個專案最後要做到什麼？")
                            OneLineSection(project: project, kind: .now, placeholder: "目前做到哪？")
                        }
                        if geo.size.width >= 760 {
                            HStack(alignment: .top, spacing: 14) {
                                TaskSection(project: project).frame(maxWidth: .infinity)
                                VStack(spacing: 14) {
                                    DecisionSection(project: project)
                                    LogSection(project: project)
                                }
                                .frame(width: min(360, geo.size.width * 0.4))
                            }
                        } else {
                            TaskSection(project: project)
                            DecisionSection(project: project)
                            LogSection(project: project)
                        }
                    }
                    .padding(18)
                }
            }
        }
    }
}

// MARK: - 頁首

struct EditorHeader: View {
    @EnvironmentObject var store: ProgressStore
    let project: ProjectProgress
    @State private var editingName = false
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if editingName {
                    TextField("專案名稱", text: $nameDraft)
                        .textFieldStyle(.roundedBorder).font(.title2)
                        .focused($nameFocused)
                        .onSubmit(saveName)
                        .onExitCommand { editingName = false }
                        .frame(maxWidth: 420)
                    Button("儲存", action: saveName)
                } else {
                    Text(project.name)
                        .font(.title2.weight(.semibold)).lineLimit(1)
                        .onTapGesture(count: 2, perform: startRename)
                        .help("雙擊可改名")
                    Button(action: startRename) { Image(systemName: "pencil") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("改名")
                }
                StatusBadge(status: project.status)
                ActivityBadge(activity: project.activity)
                Spacer()
                Menu("變更狀態") {
                    StatusMenuItems(current: project.status) { store.setStatus(project, $0) }
                }
                .fixedSize()
            }
            HStack(spacing: 12) {
                Label("更新於 \(relativeTime(project.updated))", systemImage: "clock").lineLimit(1).fixedSize()
                Button { revealInFinder(project.fileURL) } label: {
                    Label(project.fileURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "doc.text")
                        .lineLimit(1).truncationMode(.middle)
                }
                .buttonStyle(.borderless)
                .help("在 Finder 顯示 PROGRESS.md")
                Spacer()
                Button("開啟 PROGRESS.md") { NSWorkspace.shared.open(project.fileURL) }
                Button("停止追蹤…") { store.untrack(project) }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
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

// MARK: - 目標／現在（一句話）

struct OneLineSection: View {
    @EnvironmentObject var store: ProgressStore
    let project: ProjectProgress
    let kind: SectionKind
    let placeholder: String
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var text: String { kind == .goal ? project.goal : project.now }

    var body: some View {
        SectionBox(kind: kind) {
            if !editing {
                Button(action: start) { Image(systemName: "pencil") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("編輯")
            }
        } content: {
            if editing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField(placeholder, text: $draft)
                            .textFieldStyle(.roundedBorder)
                            .focused($focused)
                            .onSubmit(save)
                            .onExitCommand { editing = false }
                        Button("儲存", action: save).controlSize(.small)
                    }
                    LengthHint(text: draft)
                }
            } else if text.isEmpty {
                EmptyHint(text: placeholder)
            } else {
                Text(text)
                    .font(.title3)
                    .lineLimit(2)
                    .help(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2, perform: start)
            }
        }
    }

    private func start() {
        draft = text
        editing = true
        DispatchQueue.main.async { focused = true }
    }

    private func save() {
        editing = false
        let value = draft
        let k = kind
        store.edit(project) { doc in
            if k == .goal { doc.goal = value } else { doc.now = value }
        }
    }
}

// MARK: - 任務（第一個未完成＝下一步）

struct TaskSection: View {
    @EnvironmentObject var store: ProgressStore
    let project: ProjectProgress
    @State private var adding = false
    @State private var hideDone = false

    private var nextIndex: Int? { project.tasks.firstIndex { !$0.done } }

    var body: some View {
        SectionBox(kind: .tasks, count: project.tasks.count) {
            HStack(spacing: 8) {
                if project.doneCount > 0 {
                    Button(hideDone ? "顯示已完成" : "隱藏已完成") { hideDone.toggle() }
                        .buttonStyle(.borderless).font(.caption)
                }
                AddButton(help: "新增任務") { adding = true }
            }
        } content: {
            if !project.tasks.isEmpty {
                HStack(spacing: 8) {
                    ProgressView(value: project.fraction).tint(SectionStyle.tint(.tasks))
                    Text("\(project.doneCount)/\(project.tasks.count)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(project.tasks.enumerated()), id: \.offset) { i, task in
                if !(hideDone && task.done) {
                    EditableRow(text: task.text, dimmed: task.done, strikethrough: task.done, emphasized: i == nextIndex,
                                onSave: { new in update(i, task) { $0.text = new } },
                                onDelete: { remove(i, task) }) {
                        Button {
                            update(i, task) { $0.done.toggle() }
                        } label: {
                            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.done ? SectionStyle.tint(.tasks) : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(task.done ? "改回未完成" : "標為完成")
                    } extra: {
                        if i == nextIndex {
                            Text("下一步")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(SectionStyle.tint(.tasks).opacity(0.18), in: Capsule())
                                .foregroundStyle(SectionStyle.tint(.tasks))
                        }
                    }
                }
            }
            if project.tasks.isEmpty && !adding { EmptyHint(text: "沒有任務，按 ＋ 新增") }
            if adding {
                AddField(placeholder: "新增任務（20 字內）", isPresented: $adding) { text in
                    store.edit(project) { $0.tasks.append(TaskItem(done: false, text: text)) }
                }
            }
        }
    }

    private func update(_ i: Int, _ task: TaskItem, _ change: @escaping (inout TaskItem) -> Void) {
        store.edit(project) { doc in
            var list = doc.tasks
            guard let j = list.resolvedIndex(i, expected: task) else { return }
            change(&list[j])
            doc.tasks = list
        }
    }

    private func remove(_ i: Int, _ task: TaskItem) {
        store.edit(project) { doc in
            if let j = doc.tasks.resolvedIndex(i, expected: task) { doc.tasks.remove(at: j) }
        }
    }
}

// MARK: - 等你決定

struct DecisionSection: View {
    @EnvironmentObject var store: ProgressStore
    let project: ProjectProgress
    @State private var adding = false
    @State private var answering: Int?
    @State private var answer = ""
    @FocusState private var answerFocused: Bool

    var body: some View {
        SectionBox(kind: .decisions, count: project.decisions.count) {
            AddButton(help: "新增要決定的事") { adding = true }
        } content: {
            ForEach(Array(project.decisions.enumerated()), id: \.offset) { i, q in
                VStack(alignment: .leading, spacing: 4) {
                    EditableRow(text: q, onSave: { new in
                        store.edit(project) { doc in
                            if let j = doc.decisions.resolvedIndex(i, expected: q) { doc.decisions[j] = new }
                        }
                    }, onDelete: {
                        store.edit(project) { doc in
                            if let j = doc.decisions.resolvedIndex(i, expected: q) { doc.decisions.remove(at: j) }
                        }
                    }) {
                        Image(systemName: "questionmark.circle.fill").foregroundStyle(SectionStyle.tint(.decisions))
                    } extra: {
                        Button("回答") {
                            answer = ""
                            answering = i
                            DispatchQueue.main.async { answerFocused = true }
                        }
                        .controlSize(.small)
                        .help("寫下你的決定，Claude 下次開工會照做")
                    }
                    if answering == i {
                        HStack(spacing: 6) {
                            TextField("你的決定", text: $answer)
                                .textFieldStyle(.roundedBorder)
                                .focused($answerFocused)
                                .onSubmit { resolve(i, q) }
                                .onExitCommand { answering = nil }
                            Button("送出") { resolve(i, q) }
                                .controlSize(.small)
                                .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.leading, 22)
                    }
                }
            }
            if project.decisions.isEmpty && !adding { EmptyHint(text: "目前沒有要你決定的事") }
            if adding {
                AddField(placeholder: "需要決定的事", isPresented: $adding) { text in
                    store.edit(project) { $0.decisions.append(text) }
                }
            }
        }
    }

    /// 回答：移除問題，把決定變成「下一步」任務並記到紀錄，讓 Claude 開工時看到。
    private func resolve(_ i: Int, _ q: String) {
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty else { return }
        answering = nil
        store.edit(project) { doc in
            guard let j = doc.decisions.resolvedIndex(i, expected: q) else { return }
            doc.decisions.remove(at: j)
            var tasks = doc.tasks
            let insertAt = tasks.firstIndex { !$0.done } ?? tasks.count
            tasks.insert(TaskItem(done: false, text: "依決定：\(a)"), at: insertAt)
            doc.tasks = tasks
            doc.appendLog("（我）決定「\(q)」→ \(a)")
        }
    }
}

// MARK: - 紀錄

struct LogSection: View {
    let project: ProjectProgress
    @State private var showAll = false

    var body: some View {
        SectionBox(kind: .log, count: project.log.count) {
            if project.log.count > 5 {
                Button(showAll ? "收合" : "全部") { showAll.toggle() }.buttonStyle(.borderless).font(.caption)
            }
        } content: {
            let items = Array(project.log.reversed())
            if items.isEmpty {
                EmptyHint(text: "還沒有紀錄")
            } else {
                ForEach(Array((showAll ? items : Array(items.prefix(5))).enumerated()), id: \.offset) { _, entry in
                    LogEntry(text: entry)
                }
            }
        }
    }
}

/// 紀錄一行：時間（次要色）＋事件。
struct LogEntry: View {
    let text: String

    var body: some View {
        let parts = split(text)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(parts.time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(parts.message).font(.callout).lineLimit(2).help(parts.message)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func split(_ s: String) -> (time: String, message: String) {
        guard let r = s.range(of: #"^\d{4}-\d{2}-\d{2}( \d{2}:\d{2})?"#, options: .regularExpression) else { return ("", s) }
        let time = String(s[r]).replacingOccurrences(of: #"^\d{4}-"#, with: "", options: .regularExpression)
        return (time, s[r.upperBound...].trimmingCharacters(in: .whitespaces))
    }
}
