import Foundation
import SwiftUI

/// Runtime state of a single branch being watched. Identity is the
/// `BranchWatch.id`, not the parent `Repository.id`, so we get one row in the
/// popover per branch even when a project has multiple branch watches.
struct RepositoryState: Identifiable {
    let id: UUID                  // == BranchWatch.id
    let repositoryId: UUID
    let repositoryName: String
    let projectPath: String
    var selector: BranchSelector
    var status: PipelineStatus
    var resolvedBranch: String?
    var webUrl: String?
    var updatedAt: Date?
    var startedAt: Date?
    var baselineDuration: TimeInterval?
    var errorMessage: String?
}

@MainActor
class RepositoryStore: ObservableObject {
    @Published var states: [RepositoryState] = []
    @Published var settings: AppSettings
    @Published var globalError: String? = nil

    /// Backing UserDefaults — injectable so tests can use an isolated suite
    /// and not clobber the user's real `com.status-hub.gitlab.appSettings`.
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = AppSettings.load(from: defaults)
        syncStates()
    }

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        settings.save(to: defaults)
        syncStates()
    }

    func applyResult(_ result: PipelineResult, resolvedBranch: String, baselineDuration: TimeInterval?, forBranch branchId: UUID) {
        guard let index = states.firstIndex(where: { $0.id == branchId }) else { return }
        states[index].status = result.status
        states[index].webUrl = result.webUrl
        states[index].updatedAt = result.updatedAt
        states[index].startedAt = result.startedAt
        states[index].baselineDuration = baselineDuration
        states[index].resolvedBranch = resolvedBranch
        states[index].errorMessage = nil
        globalError = nil
        NotificationCenter.default.post(name: .repositoryStateDidChange, object: nil)
    }

    func applyError(_ error: GitLabError, forBranch branchId: UUID, resolvedBranch: String? = nil) {
        guard let index = states.firstIndex(where: { $0.id == branchId }) else { return }
        states[index].status = .unknown
        states[index].errorMessage = errorMessage(for: error)
        if let resolvedBranch {
            states[index].resolvedBranch = resolvedBranch
        }
        if case .unauthorized = error {
            globalError = "Token 无效，请检查设置"
        }
        NotificationCenter.default.post(name: .repositoryStateDidChange, object: nil)
    }

    var overallStatus: PipelineStatus {
        if states.isEmpty { return .unknown }
        if states.contains(where: { $0.status == .failed }) { return .failed }
        if states.contains(where: { $0.status == .running || $0.status == .pending }) { return .running }
        if states.allSatisfy({ $0.status == .success }) { return .success }
        return .unknown
    }

    var hubStatus: HubStatus {
        switch overallStatus {
        case .success: return .success
        case .running, .pending: return .running
        case .failed: return .failed
        case .canceled, .unknown: return states.isEmpty ? .idle : .unknown
        }
    }

    private func syncStates() {
        let existing = Dictionary(uniqueKeysWithValues: states.map { ($0.id, $0) })
        var built: [RepositoryState] = []
        for repo in settings.repositories {
            for watch in repo.branches {
                if var prior = existing[watch.id] {
                    // Repo metadata or the selector may have changed in Settings;
                    // refresh those but keep the live status fields intact.
                    prior.selector = watch.selector
                    built.append(RepositoryState(
                        id: watch.id,
                        repositoryId: repo.id,
                        repositoryName: repo.name,
                        projectPath: repo.projectPath,
                        selector: watch.selector,
                        status: prior.status,
                        resolvedBranch: prior.resolvedBranch,
                        webUrl: prior.webUrl,
                        updatedAt: prior.updatedAt,
                        startedAt: prior.startedAt,
                        baselineDuration: prior.baselineDuration,
                        errorMessage: prior.errorMessage
                    ))
                } else {
                    built.append(RepositoryState(
                        id: watch.id,
                        repositoryId: repo.id,
                        repositoryName: repo.name,
                        projectPath: repo.projectPath,
                        selector: watch.selector,
                        status: .unknown,
                        resolvedBranch: nil,
                        webUrl: nil,
                        updatedAt: nil,
                        startedAt: nil,
                        baselineDuration: nil,
                        errorMessage: nil
                    ))
                }
            }
        }
        states = built
    }

    private func errorMessage(for error: GitLabError) -> String {
        switch error {
        case .unauthorized: return "Token 无效"
        case .notFound: return "项目未找到"
        case .networkError: return "连接失败"
        case .invalidResponse: return "响应异常"
        case .noBranchMatch: return "未匹配到分支"
        }
    }
}

extension Notification.Name {
    static let repositoryStateDidChange = Notification.Name("repositoryStateDidChange")
}
