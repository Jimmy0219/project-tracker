import SwiftUI
import AppKit

/// 行前檔編輯器：新專案匯入時，Claude 會依這份指引從既有資料整理進度。
struct OnboardingBriefView: View {
    static let selectionID = "__onboarding_brief__"

    @EnvironmentObject var store: ProgressStore
    @State private var draft = ""
    @State private var saved = ""
    @State private var justSaved = false

    private var dirty: Bool { draft != saved }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass").font(.title2).foregroundStyle(.indigo)
                    Text("行前檔").font(.title2.weight(.semibold))
                    if dirty {
                        Text("尚未儲存").font(.caption.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("還原預設") { restoreDefault() }
                        .disabled(store.defaultBrief() == nil)
                        .help("換回安裝時的預設行前檔（按儲存後才生效）")
                    Button("復原變更") { draft = saved }
                        .disabled(!dirty)
                    Button {
                        store.saveBrief(draft)
                        saved = draft
                        withAnimation { justSaved = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { justSaved = false } }
                    } label: {
                        Label(justSaved ? "已儲存" : "儲存", systemImage: justSaved ? "checkmark" : "square.and.arrow.down")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!dirty)
                }
                Text("新增專案時，Claude 會讀這份指引，從專案文件、git 紀錄、過去的 Claude Code 對話與程式碼歸納出目前進度並寫入進度檔。這裡寫的是「要看什麼、怎麼整理、有什麼規則」；專案路徑等資訊會自動附上。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(store.briefURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            Divider()
            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        }
        .onAppear(perform: load)
    }

    private func load() {
        saved = store.loadBrief()
        draft = saved
    }

    private func restoreDefault() {
        if let text = store.defaultBrief() { draft = text }
    }
}
