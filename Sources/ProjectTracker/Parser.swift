import Foundation

/// 把 ~/.project-tracker/projects/*.md 轉成顯示用的 ProjectProgress。
/// agent 偶爾會寫錯格式，所以這裡盡量寬鬆：找不到的區段就留空，不會讓整份檔案失敗。
enum ProgressParser {
    static func parse(fileURL: URL) -> ProjectProgress? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let mtime = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        return parse(text: text, fileURL: fileURL, mtime: mtime)
    }

    static func parse(text: String, fileURL: URL, mtime: Date) -> ProjectProgress {
        let doc = ProgressDocument.parse(text)
        let fallbackName = fileURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"-[0-9a-f]{6}$"#, with: "", options: .regularExpression)
        var updated = mtime
        if let s = doc.value("updated"), let d = parseDate(s), d > updated { updated = d }

        return ProjectProgress(
            fileURL: fileURL,
            name: doc.name ?? fallbackName,
            projectPath: doc.value("path") ?? "",
            status: doc.status,
            agent: doc.value("agent") ?? "",
            updated: updated,
            currentState: doc.currentState,
            nextSteps: doc.nextSteps,
            todos: doc.todos,
            blockers: doc.blockers,
            history: doc.history
        )
    }

    // MARK: - 內容整理

    /// 去掉空行與「（尚未填寫…）」「（無）」這類佔位文字。
    static func meaningful(_ lines: [String]) -> [String] {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isPlaceholder($0) }
    }

    static func isPlaceholder(_ s: String) -> Bool {
        var t = s.trimmingCharacters(in: .whitespaces)
        for p in ["- [ ] ", "- [x] ", "- [?] ", "- ", "* ", "+ "] where t.hasPrefix(p) {
            t = String(t.dropFirst(p.count)); break
        }
        t = t.trimmingCharacters(in: .whitespaces)
        if ["無", "（無）", "(無)", "none", "None", "N/A", "n/a", "-", "—", "暫無", "目前無"].contains(t) { return true }
        let wrapped = (t.hasPrefix("（") && t.hasSuffix("）")) || (t.hasPrefix("(") && t.hasSuffix(")"))
        return wrapped && t.count > 2 && !t.dropFirst().dropLast().contains(where: { "）)".contains($0) })
    }

    static func stripBullet(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: #"^([-*+]|\d+[.)])\s+"#, options: .regularExpression) {
            t.removeSubrange(r)
        }
        return t
    }

    static func listItems(_ lines: [String]) -> [String] {
        meaningful(lines).map(stripBullet).filter { !$0.isEmpty }
    }

    static func todos(_ lines: [String]) -> [TodoItem] {
        meaningful(lines).compactMap { line in
            let t = stripBullet(line)
            for state in TodoState.allCases {
                for marker in state.acceptedMarkers where t.hasPrefix(marker) {
                    return TodoItem(state: state, text: t.dropFirst(marker.count).trimmingCharacters(in: .whitespaces))
                }
            }
            return nil
        }.filter { !$0.text.isEmpty && !isPlaceholder($0.text) }
    }

    static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
