import SwiftUI
import AppKit

/// 各區段的識別色與圖示：清單頁的小標籤與詳細頁的區段標題共用，方便一眼對應。
enum SectionStyle {
    static func icon(_ kind: SectionKind) -> String {
        switch kind {
        case .state: return "text.alignleft"
        case .next: return "arrow.right.circle.fill"
        case .todo: return "checklist"
        case .blockers: return "exclamationmark.triangle.fill"
        case .history: return "clock.arrow.circlepath"
        }
    }

    static func tint(_ kind: SectionKind) -> Color {
        switch kind {
        case .state: return .indigo
        case .next: return .blue
        case .todo: return .green
        case .blockers: return .orange
        case .history: return .gray
        }
    }

    static let pending = Color.purple
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

    var color: Color { Self.color(status) }

    static func color(_ status: ProjectStatus) -> Color {
        switch status {
        case .inProgress: return .blue
        case .blocked: return .orange
        case .paused: return .gray
        case .done: return .green
        case .unknown: return .secondary
        }
    }
}

/// 小型計數標籤，例如「⚠ 2 件待決」。
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

/// 狀態下拉選單（清單右鍵與詳細頁共用）。
struct StatusMenuItems: View {
    let current: ProjectStatus
    let onSelect: (ProjectStatus) -> Void

    var body: some View {
        ForEach(ProjectStatus.selectable, id: \.self) { s in
            Button {
                onSelect(s)
            } label: {
                if s == current { Label(s.label, systemImage: "checkmark") } else { Text(s.label) }
            }
        }
    }
}

/// 詳細頁的一個區段：有色圖示、標題、數量，右側可放動作按鈕。
struct SectionBox<Content: View, Accessory: View>: View {
    let kind: SectionKind
    var count: Int? = nil
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: SectionStyle.icon(kind))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(SectionStyle.tint(kind), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(kind.title).font(.subheadline.weight(.semibold))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                accessory
            }
            content
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SectionStyle.tint(kind).opacity(0.06))
        )
        .overlay(alignment: .leading) {
            // 左側色條，讓區段在捲動時也能快速辨認
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10, style: .continuous)
                .fill(SectionStyle.tint(kind).opacity(0.7))
                .frame(width: 3)
        }
    }
}

/// 區段右上角的「＋」按鈕。
struct AddButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus.circle.fill").font(.system(size: 15))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

/// 可雙擊編輯、滑過顯示刪除的單行項目。
struct EditableRow<Leading: View, Extra: View>: View {
    let text: String
    var dimmed = false
    var strikethrough = false
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
                TextField("", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                Button("儲存", action: commit).controlSize(.small)
            } else {
                Text(text)
                    .strikethrough(strikethrough)
                    .foregroundStyle(dimmed ? .secondary : .primary)
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
        .font(.callout)
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
    init(text: String, dimmed: Bool = false, strikethrough: Bool = false,
         onSave: @escaping (String) -> Void, onDelete: @escaping () -> Void,
         @ViewBuilder leading: () -> Leading) {
        self.init(text: text, dimmed: dimmed, strikethrough: strikethrough,
                  onSave: onSave, onDelete: onDelete, leading: leading, extra: { EmptyView() })
    }
}

/// 區段底部的新增輸入框（按 ＋ 後出現，Enter 新增、Esc 取消）。
struct AddField: View {
    let placeholder: String
    @Binding var isPresented: Bool
    let onAdd: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
                .onExitCommand(perform: cancel)
            Button("新增", action: commit)
                .controlSize(.small)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(action: cancel) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func commit() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        onAdd(t)
        draft = ""
        focused = true  // 保持開啟，方便連續新增
    }

    private func cancel() {
        draft = ""
        isPresented = false
    }
}

/// 沒有內容時的提示文字。
struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.tertiary)
    }
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

func revealInFinder(_ path: String) {
    guard !path.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
}
