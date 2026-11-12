import Foundation

/// 把 PROGRESS.md 轉成顯示用的 ProjectProgress；盡量寬鬆，找不到的區段就留空。
enum ProgressParser {
    static func parse(fileURL: URL) -> ProjectProgress? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let mtime = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        let doc = ProgressDocument.parse(text)
        return ProjectProgress(
            fileURL: fileURL,
            name: doc.name ?? fileURL.deletingLastPathComponent().lastPathComponent,
            status: doc.status,
            updated: mtime,
            goal: doc.goal,
            now: doc.now,
            tasks: doc.tasks,
            decisions: doc.decisions,
            log: doc.log
        )
    }

    /// 去掉空行與「（無）」「（一句話：…）」這類佔位文字。
    static func meaningful(_ lines: [String]) -> [String] {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isPlaceholder($0) }
    }

    static func isPlaceholder(_ s: String) -> Bool {
        var t = s.trimmingCharacters(in: .whitespaces)
        for p in ["- [ ] ", "- [x] ", "- ", "* ", "+ "] where t.hasPrefix(p) {
            t = String(t.dropFirst(p.count)); break
        }
        t = t.trimmingCharacters(in: .whitespaces)
        if ["無", "（無）", "(無)", "none", "None", "N/A", "-", "—"].contains(t) { return true }
        let wrapped = (t.hasPrefix("（") && t.hasSuffix("）")) || (t.hasPrefix("(") && t.hasSuffix(")"))
        return wrapped && t.count > 2 && !t.dropFirst().dropLast().contains(where: { "）)".contains($0) })
    }

    static func stripBullet(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: #"^([-*+]|\d+[.)])\s+"#, options: .regularExpression) { t.removeSubrange(r) }
        return t
    }

    static func listItems(_ lines: [String]) -> [String] {
        meaningful(lines).map(stripBullet).filter { !$0.isEmpty }
    }

    static func tasks(_ lines: [String]) -> [TaskItem] {
        meaningful(lines).compactMap { line in
            let t = stripBullet(line)
            for (marker, done) in [("[x]", true), ("[X]", true), ("[ ]", false), ("[?]", true)] where t.hasPrefix(marker) {
                return TaskItem(done: done, text: t.dropFirst(marker.count).trimmingCharacters(in: .whitespaces))
            }
            return nil
        }.filter { !$0.text.isEmpty && !isPlaceholder($0.text) }
    }
}
