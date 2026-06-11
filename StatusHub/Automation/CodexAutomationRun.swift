import Foundation

struct AutomationArtifact: Codable, Identifiable, Equatable {
    var id: String { url ?? title }
    let title: String
    let url: String?
}

struct CodexAutomationRun: Codable, Identifiable, Equatable {
    let runId: String
    let jobType: String
    let status: AutomationRunStatus
    let trigger: String?
    let startedAt: Date?
    let finishedAt: Date?
    let sprint: String?
    let summary: String?
    let artifacts: [AutomationArtifact]
    let logPath: String?
    var note: String?

    var id: String { runId }

    var displayTitle: String {
        switch jobType {
        case "daily-feedback-defect-triage": return "每日缺陷反馈分析"
        case "prepare-sprint-iteration": return "迭代需求整理"
        case "track-sprint-demand-progress": return "迭代进度追踪"
        default: return jobType
        }
    }
}

enum AutomationRunStatus: String, Codable {
    case pending
    case running
    case success
    case failed
    case needsConfirmation = "needs_confirmation"
    case canceled
    case unknown

    var hubStatus: HubStatus {
        switch self {
        case .pending, .running: return .running
        case .success: return .success
        case .failed: return .failed
        case .needsConfirmation: return .attention
        case .canceled, .unknown: return .unknown
        }
    }

    var label: String {
        switch self {
        case .pending: return "等待中"
        case .running: return "运行中"
        case .success: return "成功"
        case .failed: return "失败"
        case .needsConfirmation: return "待确认"
        case .canceled: return "已取消"
        case .unknown: return "未知"
        }
    }
}
