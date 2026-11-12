import SwiftUI
import AppKit

/// 各區段的識別色與圖示（選單列、側欄、編輯區共用，方便一眼對應）。
enum SectionStyle {
    static func icon(_ kind: SectionKind) -> String {
        switch kind {
        case .goal: return "flag.fill"
        case .now: return "location.fill"
        case .tasks: return "checklist"
        case .decisions: return "questionmark.bubble.fill"
        case .log: return "clock.arrow.circlepath"
        }
    }

    static func tint(_ kind: SectionKind) -> Color {
        switch kind {
        case .goal: return .indigo
        case .now: return .blue
        case .tasks: return .green
        case .decisions: return .orange
        case .log: return .gray
        }
    }
}

struct StatusBadge: View {
    let status: ProjectStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Self.color(status).opacity(0.18), in: Capsule())
            .foregroundStyle(Self.color(status))
    }

    static func color(_ status: ProjectStatus) -> Color {
        switch status {
        case .inProgress: return .blue
        case .paused: return .gray
        case .done: return .green
        }
    }
}

/// Claude 活動燈號：工作中（綠色閃爍）／上次活動時間。
struct ActivityBadge: View {
    let activity: Activity
    var compact = false
    @State private var pulse = false

    var body: some View {
        switch activity {
        case .working:
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 7, height: 7)
                    .opacity(pulse ? 0.35 : 1)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
                Text("Claude 工作中").font(.caption.weight(.medium)).foregroundStyle(.green)
            }
            .help("最近 2 分鐘內這個專案的 Claude Code 對話有動作")
        case .idle(let date):
            if !compact {
                Text("Claude \(relativeTime(date))活動").font(.caption).foregroundStyle(.secondary)
            }
        case .unknown:
            EmptyView()
        }
    }
}

/// 小型計數標籤，例如「? 2 件等你決定」。
struct CountChip: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

struct StatusMenuItems: View {
    let current: ProjectStatus
    let onSelect: (ProjectStatus) -> Void

    var body: some View {
        ForEach(ProjectStatus.allCases, id: \.self) { s in
            Button {
                onSelect(s)
            } label: {
                if s == current { Label(s.label, systemImage: "checkmark") } else { Text(s.label) }
            }
        }
    }
}

/// 編輯區的一個區段：有色圖示、標題、數量，右側可放動作按鈕。
struct SectionBox<Content: View, Accessory: View>: View {
    let kind: SectionKind
    var count: Int? = nil
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: SectionStyle.icon(kind))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(SectionStyle.tint(kind), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(kind.title).font(.headline)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                accessory
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SectionStyle.tint(kind).opacity(0.06)))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10, style: .continuous)
                .fill(SectionStyle.tint(kind).opacity(0.7))
                .frame(width: 3)
        }
    }
}

struct AddButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "plus.circle.fill").font(.system(size: 15)) }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(help)
    }
}

/// 可雙擊編輯、滑過顯示編輯／刪除的單行項目；超過 20 字會提醒。
struct EditableRow<Leading: View, Extra: View>: View {
    let text: String
    var dimmed = false
    var strikethrough = false
    var emphasized = false
    let onSave: (String) -> Void
    let onDelete: () -> Void
    @ViewBuilder var leading: Leading
    @ViewBuilder var extra: Extra

    @State private var editing = false
    @State private var draft = ""
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            leading
            if editing {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit(commit)
                        .onExitCommand { editing = false }
                    LengthHint(text: draft)
                }
                Button("儲存", action: commit).controlSize(.small)
            } else {
                Text(text)
                    .fontWeight(emphasized ? .semibold : .regular)
                    .strikethrough(strikethrough)
                    .foregroundStyle(dimmed ? .secondary : .primary)
                    .lineLimit(1)
                    .help(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: startEditing)
                extra
                HStack(spacing: 6) {
                    Button(action: startEditing) { Image(systemName: "pencil") }.help("編輯")
                    Button(action: onDelete) { Image(systemName: "trash") }.help("刪除")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
            }
        }
        .font(.body)
        .onHover { hovering = $0 }
    }

    private func startEditing() {
        draft = text
        editing = true
        DispatchQueue.main.async { focused = true }
    }

    private func commit() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = false
        if !t.isEmpty, t != text { onSave(t) }
    }
}

extension EditableRow where Extra == EmptyView {
    init(text: String, dimmed: Bool = false, strikethrough: Bool = false, emphasized: Bool = false,
         onSave: @escaping (String) -> Void, onDelete: @escaping () -> Void,
         @ViewBuilder leading: () -> Leading) {
        self.init(text: text, dimmed: dimmed, strikethrough: strikethrough, emphasized: emphasized,
                  onSave: onSave, onDelete: onDelete, leading: leading, extra: { EmptyView() })
    }
}

/// 超過 20 字時的小提醒。
struct LengthHint: View {
    let text: String
    var body: some View {
        if text.count > 20 {
            Text("\(text.count) 字，建議 20 字內").font(.caption2).foregroundStyle(.orange)
        }
    }
}

/// 區段底部的新增輸入框（Enter 新增、可連續新增、Esc 取消）。
struct AddField: View {
    let placeholder: String
    @Binding var isPresented: Bool
    let onAdd: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
                LengthHint(text: draft)
            }
            Button("新增", action: commit)
                .controlSize(.small)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(action: cancel) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .font(.body)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func commit() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        onAdd(t)
        draft = ""
        focused = true
    }

    private func cancel() {
        draft = ""
        isPresented = false
    }
}

struct EmptyHint: View {
    let text: String
    var body: some View { Text(text).font(.caption).foregroundStyle(.tertiary) }
}

func relativeTime(_ date: Date, now: Date = Date()) -> String {
    if now.timeIntervalSince(date) < 60 { return "剛剛" }
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "zh-Hant-TW")
    f.unitsStyle = .short
    return f.localizedString(for: date, relativeTo: now)
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}
