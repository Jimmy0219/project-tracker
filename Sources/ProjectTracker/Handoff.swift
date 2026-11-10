import Foundation

/// 組出可以直接貼給新 agent 的交接 prompt。
enum Handoff {
    static func prompt(for p: ProjectProgress) -> String {
        var out: [String] = []
        let path = p.projectPath.isEmpty ? "" : "（路徑：\(p.projectPath)）"
        out.append("請接手專案「\(p.name)」\(path)。")
        out.append("進度檔：\(p.fileURL.path)——開工前請先讀，收工前依其格式更新（ptrack log／ptrack stamp）。")
        let meta = [
            "狀態：\(p.effectiveStatus.label)",
            p.totalCount > 0 ? "待辦完成 \(p.doneCount)/\(p.totalCount)" : nil,
            p.agent.isEmpty ? nil : "上次由 \(p.agent) 更新",
        ].compactMap { $0 }
        out.append(meta.joined(separator: "；"))

        if !p.currentState.isEmpty {
            out.append("\n## 目前狀態\n\(p.currentState)")
        }
        if !p.nextSteps.isEmpty {
            out.append("\n## 下一步\n" + p.nextSteps.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !p.openTodos.isEmpty {
            out.append("\n## 未完成待辦\n" + p.openTodos.map { "- [ ] \($0.text)" }.joined(separator: "\n"))
        }
        if !p.blockers.isEmpty {
            out.append("\n## 卡關／待決事項\n" + p.blockers.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !p.history.isEmpty {
            out.append("\n## 最近歷程\n" + p.history.suffix(3).map { "- \($0)" }.joined(separator: "\n"))
        }
        out.append("\n請先確認上述內容與程式碼現況一致，再從「下一步」開始。")
        return out.joined(separator: "\n")
    }
}
