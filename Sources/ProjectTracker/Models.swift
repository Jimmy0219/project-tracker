import Foundation

enum ProjectStatus: String, CaseIterable {
    case inProgress = "in_progress"
    case blocked
    case paused
    case done
    case unknown

    init(raw: String) {
        let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch key {
        case "in_progress", "inprogress", "active", "wip", "進行中": self = .inProgress
        case "blocked", "卡關": self = .blocked
        case "paused", "on_hold", "暫停": self = .paused
        case "done", "completed", "finished", "完成", "已完成": self = .done
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .inProgress: return "進行中"
        case .blocked: return "卡關"
        case .paused: return "暫停"
        case .done: return "已完成"
        case .unknown: return "未標示"
        }
    }
}

struct TodoItem: Hashable {
    let done: Bool
    let text: String
}

struct ProjectProgress: Identifiable {
    var id: String { fileURL.path }
    let fileURL: URL
    var name: String
    var projectPath: String
    var status: ProjectStatus
    var agent: String
    var updated: Date
    var currentState: String
    var nextSteps: [String]
    var todos: [TodoItem]
    var blockers: [String]
    var history: [String]

    var doneCount: Int { todos.filter(\.done).count }
    var totalCount: Int { todos.count }
    var fraction: Double { totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount) }
    var openTodos: [TodoItem] { todos.filter { !$0.done } }

    /// 有卡關事項但狀態仍標示進行中時，顯示為卡關。
    var effectiveStatus: ProjectStatus {
        if status == .done || status == .paused { return status }
        return blockers.isEmpty ? (status == .blocked ? .blocked : status) : .blocked
    }

    /// 需要使用者注意的事項數（已完成／暫停的專案不計）。
    var attentionCount: Int {
        (status == .done || status == .paused) ? 0 : blockers.count
    }
}
