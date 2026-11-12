import SwiftUI
import AppKit

/// 匯入說明：丟給專案的 Claude Code，讓它建立 PROGRESS.md 並設定回報規則。
struct ImportGuideView: View {
    static let selectionID = "__import_guide__"

    @EnvironmentObject var store: ProgressStore
    @State private var draft = ""
    @State private var saved = ""
    @State private var copied = false

    private var dirty: Bool { draft != saved }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("匯入新專案").font(.title2.weight(.semibold))
                HStack(alignment: .top, spacing: 12) {
                    StepCard(number: 1, title: "丟給 Claude", detail: "把下面的檔案拖進該專案的 Claude Code 對話框（或複製全文貼上）")
                    StepCard(number: 2, title: "Claude 建檔", detail: "它會在專案根目錄建立 PROGRESS.md，並在 CLAUDE.md 加入回報規則")
                    StepCard(number: 3, title: "拖回來", detail: "把 PROGRESS.md 拖進這個視窗；之後 Claude 每完成一項就會即時更新")
                }
                HStack(spacing: 10) {
                    // 可直接拖進 Claude Code 的檔案
                    HStack(spacing: 8) {
                        Image(systemName: "doc.richtext").font(.title2).foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("import-guide.md").font(.body.weight(.medium))
                            Text("拖曳我到 Claude Code").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.indigo.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .onDrag { NSItemProvider(contentsOf: store.guideURL) ?? NSItemProvider() }
                    .help("把這個檔案拖進 Claude Code 的對話框")

                    Button {
                        copyToPasteboard(saved)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { copied = false } }
                    } label: {
                        Label(copied ? "已複製" : "複製全文", systemImage: copied ? "checkmark" : "doc.on.clipboard")
                    }
                    Button { revealInFinder(store.guideURL) } label: {
                        Label("在 Finder 顯示", systemImage: "folder")
                    }
                    Spacer()
                }
            }
            .padding(18)
            Divider()
            HStack {
                Text("說明內容（可修改）").font(.headline)
                if dirty {
                    Text("尚未儲存").font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("還原預設") { if let d = store.defaultGuide() { draft = d } }
                    .disabled(store.defaultGuide() == nil)
                Button("復原變更") { draft = saved }.disabled(!dirty)
                Button("儲存") {
                    store.saveGuide(draft)
                    saved = draft
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!dirty)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            TextEditor(text: $draft)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        }
        .onAppear {
            saved = store.loadGuide()
            draft = saved
        }
    }
}

struct StepCard: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}
