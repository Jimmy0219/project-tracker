import Foundation

enum ProjectStatus: String, CaseIterable {
    case inProgress = "in_progress"
    case paused
    case done

    init(raw: String) {
        let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch key {
        case "paused", "on_hold", "暫停": self = .paused
        case "done", "completed", "finished", "完成", "已完成": self = .done
        default: self = .inProgress
        }
    }

    var label: String {
        switch self {
        case .inProgress: return "進行中"
        case .paused: return "暫停"
        case .done: return "完成"
        }
    }
}

struct TaskItem: Hashable {
    var done: Bool
    var text: String
}

/// Claude Code 在這個專案的活動狀態（由對話紀錄檔的修改時間推得）。
enum Activity: Equatable {
    case working            // 最近 2 分鐘內有動作
    case idle(Date)         // 上次活動時間
    case unknown            // 找不到對話紀錄
}

struct ProjectProgress: Identifiable {
    var id: String { fileURL.path }
    let fileURL: URL
    var name: String
    var status: ProjectStatus
    var updated: Date
    var goal: String
    var now: String
    var tasks: [TaskItem]
    var decisions: [String]
    var log: [String]
    var activity: Activity = .unknown

    var projectURL: URL { fileURL.deletingLastPathComponent() }
    var doneCount: Int { tasks.filter(\.done).count }
    var fraction: Double { tasks.isEmpty ? 0 : Double(doneCount) / Double(tasks.count) }
    /// 第一個未完成的任務＝下一步
    var nextTask: String? { tasks.first { !$0.done }?.text }
    var isActive: Bool { status == .inProgress }
    /// 需要使用者處理的事（暫停／完成的專案不計）
    var attentionCount: Int { isActive ? decisions.count : 0 }
    var isWorking: Bool { activity == .working }
}
