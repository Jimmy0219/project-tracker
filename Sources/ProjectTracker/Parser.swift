import Foundation

/// 解析 ~/.project-tracker/projects/*.md（Markdown + YAML frontmatter）。
/// agent 偶爾會寫錯格式，所以這裡盡量寬鬆：找不到的區段就留空，不會讓整份檔案失敗。
enum ProgressParser {
    static func parse(fileURL: URL) -> ProjectProgress? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let mtime = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        return parse(text: text, fileURL: fileURL, mtime: mtime)
    }

    static func parse(text: String, fileURL: URL, mtime: Date) -> ProjectProgress {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let (front, body) = splitFrontmatter(normalized)
        let sections = splitSections(body)

        func section(_ keys: [String]) -> [String] {
            for (title, lines) in sections where keys.contains(where: { title.contains($0) }) {
                return lines
            }
            return []
        }

        let fallbackName = fileURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"-[0-9a-f]{6}$"#, with: "", options: .regularExpression)
        var updated = mtime
        if let s = front["updated"], let d = parseDate(s), d > updated { updated = d }

        return ProjectProgress(
            fileURL: fileURL,
            name: nonEmpty(front["project"]) ?? fallbackName,
            projectPath: front["path"] ?? "",
            status: ProjectStatus(raw: front["status"] ?? ""),
            agent: front["agent"] ?? "",
            updated: updated,
            currentState: meaningful(section(["目前狀態", "狀態", "Status"])).joined(separator: "\n"),
            nextSteps: listItems(section(["下一步", "Next"])),
            todos: todos(section(["待辦", "TODO", "Todo", "Tasks"])),
            blockers: listItems(section(["卡關", "待決", "Blocker"])),
            history: listItems(section(["歷程", "History", "Log"]))
        )
    }

    // MARK: - 區塊切分

    static func splitFrontmatter(_ text: String) -> ([String: String], String) {
        guard text.hasPrefix("---\n") else { return ([:], text) }
        let rest = text.dropFirst(4)
        guard let end = rest.range(of: "\n---") else { return ([:], text) }
        var dict: [String: String] = [:]
        for line in rest[..<end.lowerBound].split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let f = value.first, f == "\"" || f == "'", value.last == f {
                value = String(value.dropFirst().dropLast())
            }
            dict[key] = value
        }
        var body = rest[end.upperBound...]
        if let nl = body.firstIndex(of: "\n") { body = body[body.index(after: nl)...] } else { body = "" }
        return (dict, String(body))
    }

    static func splitSections(_ body: String) -> [(String, [String])] {
        var result: [(String, [String])] = []
        var title: String?
        var lines: [String] = []
        for raw in body.components(separatedBy: "\n") {
            if raw.hasPrefix("## ") || raw.hasPrefix("### ") {
                if let t = title { result.append((t, lines)) }
                title = raw.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                lines = []
            } else if title != nil {
                lines.append(raw)
            }
        }
        if let t = title { result.append((t, lines)) }
        return result
    }

    // MARK: - 內容整理

    /// 去掉空行與「（尚未填寫…）」「（無）」這類佔位文字。
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
            if t.hasPrefix("[x]") || t.hasPrefix("[X]") {
                return TodoItem(done: true, text: t.dropFirst(3).trimmingCharacters(in: .whitespaces))
            }
            if t.hasPrefix("[ ]") {
                return TodoItem(done: false, text: t.dropFirst(3).trimmingCharacters(in: .whitespaces))
            }
            return nil
        }.filter { !$0.text.isEmpty && !isPlaceholder($0.text) }
    }

    static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
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
