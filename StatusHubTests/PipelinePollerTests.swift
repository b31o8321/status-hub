import XCTest
@testable import StatusHub

@MainActor
final class PipelinePollerTests: XCTestCase {

    /// Build a fresh, per-test UserDefaults so RepositoryStore writes never
    /// touch the user's real `com.status-hub.gitlab.appSettings`.
    static func isolatedDefaults() -> UserDefaults {
        let suite = "status-hub.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    final class MockGitLabService: GitLabServiceProtocol {
        var pipelineResult: Result<PipelineResult, GitLabError>
        var branchesByPath: [String] = []

        init(result: Result<PipelineResult, GitLabError>, branches: [String] = []) {
            self.pipelineResult = result
            self.branchesByPath = branches
        }

        func fetchLatestPipeline(gitlabUrl: String, projectPath: String, branch: String, token: String) async throws -> PipelineResult {
            switch pipelineResult {
            case .success(let r): return r
            case .failure(let e): throw e
            }
        }

        func fetchRecentSuccessDurations(gitlabUrl: String, projectPath: String, branch: String, token: String, limit: Int) async throws -> [TimeInterval] {
            return []
        }

        func fetchProjects(gitlabUrl: String, token: String, search: String) async throws -> [GitLabProject] { [] }
        func fetchBranches(gitlabUrl: String, token: String, projectId: Int) async throws -> [GitLabBranch] { [] }
        func fetchBranches(gitlabUrl: String, token: String, projectPath: String, search: String?) async throws -> [GitLabBranch] {
            return branchesByPath.map { GitLabBranch(name: $0) }
        }
    }

    func testPollerUpdatesStoreOnSuccess() async throws {
        let store = RepositoryStore(defaults: Self.isolatedDefaults())
        let repo = Repository(name: "test", projectPath: "group/project", branch: "main")
        var settings = AppSettings.default
        settings.gitlabUrl = "https://gitlab.example.com"
        settings.repositories = [repo]
        store.updateSettings(settings)

        let mockResult = PipelineResult(
            status: .success,
            webUrl: "https://gitlab.example.com/group/project/-/pipelines/1",
            updatedAt: Date(),
            startedAt: nil
        )
        let mockService = MockGitLabService(result: .success(mockResult))
        let poller = PipelinePoller(store: store, service: mockService)

        await poller.pollOnce(token: "test-token")

        XCTAssertEqual(store.states.first?.status, .success)
        XCTAssertNil(store.states.first?.errorMessage)
        XCTAssertEqual(store.states.first?.resolvedBranch, "main")
    }

    func testPollerUpdatesStoreOnError() async throws {
        let store = RepositoryStore(defaults: Self.isolatedDefaults())
        let repo = Repository(name: "test", projectPath: "group/project", branch: "main")
        var settings = AppSettings.default
        settings.gitlabUrl = "https://gitlab.example.com"
        settings.repositories = [repo]
        store.updateSettings(settings)

        let mockService = MockGitLabService(result: .failure(.notFound))
        let poller = PipelinePoller(store: store, service: mockService)

        await poller.pollOnce(token: "test-token")

        XCTAssertEqual(store.states.first?.status, .unknown)
        XCTAssertEqual(store.states.first?.errorMessage, "项目未找到")
    }

    func testPollerWithRuleResolvesLatestBranchAndPolls() async throws {
        let store = RepositoryStore(defaults: Self.isolatedDefaults())
        let repo = Repository(
            name: "test",
            projectPath: "group/project",
            branchSelector: .rule(prefix: "test", format: .yyyymmdd)
        )
        var settings = AppSettings.default
        settings.gitlabUrl = "https://gitlab.example.com"
        settings.repositories = [repo]
        store.updateSettings(settings)

        let mockResult = PipelineResult(
            status: .running,
            webUrl: "https://gitlab.example.com/x",
            updatedAt: Date(),
            startedAt: nil
        )
        let mockService = MockGitLabService(
            result: .success(mockResult),
            branches: ["test-20260128", "test-20260326", "main"]
        )
        let poller = PipelinePoller(store: store, service: mockService)

        await poller.pollOnce(token: "test-token")

        XCTAssertEqual(store.states.first?.status, .running)
        XCTAssertEqual(store.states.first?.resolvedBranch, "test-20260326")
    }

    func testPollerSetsNoBranchMatchErrorWhenRuleMisses() async throws {
        let store = RepositoryStore(defaults: Self.isolatedDefaults())
        let repo = Repository(
            name: "test",
            projectPath: "group/project",
            branchSelector: .rule(prefix: "test", format: .yyyymmdd)
        )
        var settings = AppSettings.default
        settings.gitlabUrl = "https://gitlab.example.com"
        settings.repositories = [repo]
        store.updateSettings(settings)

        let mockService = MockGitLabService(
            result: .failure(.notFound),  // not used; pipeline call should be skipped
            branches: ["main", "develop"]
        )
        let poller = PipelinePoller(store: store, service: mockService)

        await poller.pollOnce(token: "test-token")

        XCTAssertEqual(store.states.first?.status, .unknown)
        XCTAssertEqual(store.states.first?.errorMessage, "未匹配到分支")
    }
}
