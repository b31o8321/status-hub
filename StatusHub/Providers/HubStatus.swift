import SwiftUI

enum HubStatus: String, Codable, Comparable {
    case idle
    case success
    case running
    case attention
    case failed
    case unknown

    static func < (lhs: HubStatus, rhs: HubStatus) -> Bool {
        lhs.severity < rhs.severity
    }

    var severity: Int {
        switch self {
        case .idle: return 0
        case .success: return 1
        case .unknown: return 2
        case .running: return 3
        case .attention: return 4
        case .failed: return 5
        }
    }

    var color: Color {
        switch self {
        case .idle, .unknown: return .gray
        case .success: return .green
        case .running: return .yellow
        case .attention: return .orange
        case .failed: return .red
        }
    }

    var label: String {
        switch self {
        case .idle: return "空闲"
        case .success: return "正常"
        case .running: return "运行中"
        case .attention: return "待确认"
        case .failed: return "失败"
        case .unknown: return "未知"
        }
    }
}
