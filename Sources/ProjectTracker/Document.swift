import Foundation

/// PROGRESS.md 的區段與標準標題（新建區段時也依此順序）。
enum SectionKind: CaseIterable {
    case goal, now, tasks, decisions, log

    var title: String {
        switch self {
        case .goal: return "目標"
        case .now: return "現在"
        case .tasks: return "任務"
        case .decisions: return "等你決定"
        case .log: return "紀錄"
        }
    }

    /// 比對既有標題用的關鍵字（容許 agent 寫得略有不同）。
    var keys: [String] {
        switch self {
        case .goal: return ["目標", "Goal"]
        case .now: return ["現在", "目前", "狀態", "Now", "Status"]
        case .tasks: return ["任務", "待辦", "TODO", "Tasks"]
        case .decisions: return ["等你決定", "待決", "決定", "卡關", "Decision", "Question"]
        case .log: return ["紀錄", "歷程", "Log", "History"]
        }
    }

    static func match(_ title: String) -> SectionKind? {
        for kind in [SectionKind.decisions, .tasks, .log, .goal, .now]
        where kind.keys.contains(where: { title.contains($0) }) {
            return kind
        }
        return nil
    }
}

/// 可讀可寫的進度檔：保留 frontmatter 原始行、未知區段與順序，只改寫被編輯的區段。
struct ProgressDocument {
    var frontLines: [String]
    var preamble: [String]
    var sections: [(title: String, lines: [String])]

    static func parse(_ text: String) -> ProgressDocument {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var front: [String] = []
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            front = Array(lines[1..<end])
            lines = Array(lines[(end + 1)...])
        }
        var preamble: [String] = []
        var sections: [(String, [String])] = []
        for line in lines {
            if line.hasPrefix("## ") || line.hasPrefix("### ") {
                sections.append((line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces), []))
            } else if sections.isEmpty {
                preamble.append(line)
            } else {
                sections[sections.count - 1].1.append(line)
            }
        }
        return ProgressDocument(frontLines: front, preamble: preamble,
                                sections: sections.map { (title: $0.0, lines: $0.1) })
    }

    func serialize() -> String {
        var out = ["---"] + frontLines + ["---"]
        out += preamble.isEmpty ? [""] : preamble
        for s in sections {
            out.append("## \(s.title)")
            out += s.lines
        }
        while out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: frontmatter

    func value(_ key: String) -> String? {
        for line in frontLines {
            guard let colon = line.firstIndex(of: ":"),
                  line[..<colon].trimmingCharacters(in: .whitespaces) == key else { continue }
            var v = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let hash = v.range(of: " #") { v = v[..<hash.lowerBound].trimmingCharacters(in: .whitespaces) }
            if v.count >= 2, let f = v.first, f == "\"" || f == "'", v.last == f {
                v = String(v.dropFirst().dropLast())
            }
            return v
        }
        return nil
    }

    mutating func set(_ key: String, _ value: String) {
        let line = "\(key): \(value)"
        if let i = frontLines.firstIndex(where: {
            guard let c = $0.firstIndex(of: ":") else { return false }
            return $0[..<c].trimmingCharacters(in: .whitespaces) == key
        }) {
            frontLines[i] = line
        } else {
            frontLines.append(line)
        }
    }

    // MARK: 區段

    func lines(_ kind: SectionKind) -> [String] {
        sections.first(where: { SectionKind.match($0.title) == kind })?.lines ?? []
    }

    mutating func setLines(_ kind: SectionKind, _ newLines: [String]) {
        if let i = sections.firstIndex(where: { SectionKind.match($0.title) == kind }) {
            sections[i].lines = newLines
            return
        }
        let order = SectionKind.allCases
        let myRank = order.firstIndex(of: kind)!
        let insertAt = sections.firstIndex(where: {
            guard let k = SectionKind.match($0.title), let r = order.firstIndex(of: k) else { return false }
            return r > myRank
        }) ?? sections.count
        sections.insert((title: kind.title, lines: newLines), at: insertAt)
    }

    private mutating func setText(_ kind: SectionKind, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        setLines(kind, [""] + (t.isEmpty ? [] : t.components(separatedBy: "\n")) + [""])
    }

    private mutating func setList(_ kind: SectionKind, _ items: [String], empty: String? = nil) {
        let body = items.isEmpty ? (empty.map { [$0] } ?? []) : items
        setLines(kind, [""] + body + [""])
    }

    // MARK: 高階讀寫（App 顯示與編輯共用）

    var name: String? { value("project").flatMap { $0.isEmpty ? nil : $0 } }
    var status: ProjectStatus { ProjectStatus(raw: value("status") ?? "") }

    var goal: String {
        get { ProgressParser.meaningful(lines(.goal)).joined(separator: " ") }
        set { setText(.goal, newValue) }
    }

    var now: String {
        get { ProgressParser.meaningful(lines(.now)).joined(separator: " ") }
        set { setText(.now, newValue) }
    }

    var tasks: [TaskItem] {
        get { ProgressParser.tasks(lines(.tasks)) }
        set { setList(.tasks, newValue.map { "- [\($0.done ? "x" : " ")] \($0.text)" }) }
    }

    var decisions: [String] {
        get { ProgressParser.listItems(lines(.decisions)) }
        set { setList(.decisions, newValue.map { "- \($0)" }, empty: "（無）") }
    }

    var log: [String] { ProgressParser.listItems(lines(.log)) }

    mutating func appendLog(_ message: String) {
        var l = lines(.log)
        while l.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { l.removeLast() }
        if l.isEmpty { l = [""] }
        l.append("- \(Self.shortNow()) \(message)")
        l.append("")
        setLines(.log, l)
    }

    static func shortNow() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }
}

/// 「重新讀檔 → 修改 → 原子寫回」，降低和正在工作的 Claude 互相覆蓋的機會。
enum ProgressEditor {
    static func mutate(_ url: URL, _ change: (inout ProgressDocument) -> Void) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var doc = ProgressDocument.parse(text)
        change(&doc)
        try doc.serialize().write(to: url, atomically: true, encoding: .utf8)
    }
}

extension Array where Element: Equatable {
    /// 依索引操作前先確認內容沒變；檔案若已被別人改過，就改用內容比對找位置。
    func resolvedIndex(_ index: Int, expected: Element) -> Int? {
        if indices.contains(index), self[index] == expected { return index }
        return firstIndex(of: expected)
    }
}
