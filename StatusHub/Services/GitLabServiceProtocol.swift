import Foundation

struct PipelineResult {
    let status: PipelineStatus
    let webUrl: String
    let updatedAt: Date
    let startedAt: Date?
}

protocol GitLabServiceProtocol {
    func fetchLatestPipeline(
        gitlabUrl: String,
        projectPath: String,
        branch: String,
        token: String
    ) async throws -> PipelineResult

    /// Returns the recent successful pipeline durations (seconds) on a branch,
    /// ordered newest first. Used to estimate how long a running pipeline will take.
    func fetchRecentSuccessDurations(
        gitlabUrl: String,
        projectPath: String,
        branch: String,
        token: String,
        limit: Int
    ) async throws -> [TimeInterval]

    func fetchProjects(
        gitlabUrl: String,
        token: String,
        search: String
    ) async throws -> [GitLabProject]

    func fetchBranches(
        gitlabUrl: String,
        token: String,
        projectId: Int
    ) async throws -> [GitLabBranch]

    func fetchBranches(
        gitlabUrl: String,
        token: String,
        projectPath: String,
        search: String?
    ) async throws -> [GitLabBranch]
}

enum GitLabError: Error, LocalizedError {
    case unauthorized
    case notFound
    case networkError(Error)
    case invalidResponse
    case noBranchMatch

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Token 无效或权限不足 (401)"
        case .notFound: return "找不到资源，请检查 GitLab 地址 (404)"
        case .networkError(let e): return "网络错误：\(e.localizedDescription)"
        case .invalidResponse: return "服务器返回了无效的响应"
        case .noBranchMatch: return "未匹配到分支"
        }
    }
}
