import SwiftUI

enum PipelineStatus: String, Codable {
    case running
    case pending
    case success
    case failed
    case canceled
    case unknown

    var color: Color {
        switch self {
        case .running, .pending: return .yellow
        case .success: return .green
        case .failed: return .red
        case .canceled, .unknown: return .gray
        }
    }

    var label: String {
        switch self {
        case .running: return "运行中"
        case .pending: return "等待中"
        case .success: return "成功"
        case .failed: return "失败"
        case .canceled: return "已取消"
        case .unknown: return "未知"
        }
    }

    var symbol: String {
        switch self {
        case .running: return "↻"
        case .pending: return "…"
        case .success: return "✓"
        case .failed: return "✗"
        case .canceled: return "⊘"
        case .unknown: return "?"
        }
    }
}
