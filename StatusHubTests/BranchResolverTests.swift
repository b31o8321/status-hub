import XCTest
@testable import StatusHub

final class BranchResolverTests: XCTestCase {

    final class MockService: GitLabServiceProtocol {
        var branches: [String] = []
        var lastSearch: String??
        var lastProjectPath: String?
        var fetchBranchesCallCount = 0

        func fetchLatestPipeline(gitlabUrl: String, projectPath: String, branch: String, token: String) async throws -> PipelineResult {
            fatalError("not used")
        }

        func fetchProjects(gitlabUrl: String, token: String, search: String) async throws -> [GitLabProject] {
            return []
        }

        func fetchBranches(gitlabUrl: String, token: String, projectId: Int) async throws -> [GitLabBranch] {
            return []
        }

        func fetchBranches(gitlabUrl: String, token: String, projectPath: String, search: String?) async throws -> [GitLabBranch] {
            fetchBranchesCallCount += 1
            lastSearch = search
            lastProjectPath = projectPath
            return branches.map { GitLabBranch(name: $0) }
        }

        func fetchRecentSuccessDurations(gitlabUrl: String, projectPath: String, branch: String, token: String, limit: Int) async throws -> [TimeInterval] {
            return []
        }
    }

    func testFixedReturnsLiteralAndDoesNotCallApi() async throws {
        let mock = MockService()
        let resolver = BranchResolver(service: mock)
        let resolved = try await resolver.resolve(
            selector: .fixed("staging"),
            gitlabUrl: "https://gitlab.example.com",
            projectPath: "group/svc",
            token: "t"
        )
        XCTAssertEqual(resolved, "staging")
        XCTAssertEqual(mock.fetchBranchesCallCount, 0)
    }

    func testRulePicksLargestDateMatchingPattern() async throws {
        let mock = MockService()
        mock.branches = [
            "test-20260128",
            "test-20260326",
            "test-feature",
            "main",
            "test-20260201"
        ]
        let resolver = BranchResolver(service: mock)
        let resolved = try await resolver.resolve(
            selector: .rule(prefix: "test", format: .yyyymmdd),
            gitlabUrl: "https://gitlab.example.com",
            projectPath: "group/svc",
            token: "t"
        )
        XCTAssertEqual(resolved, "test-20260326")
        // search prefix is forwarded
        XCTAssertEqual(mock.lastSearch, "^test-")
    }

    func testRuleReturnsNilWhenNoMatch() async throws {
        let mock = MockService()
        mock.branches = ["main", "develop", "test-feature"]
        let resolver = BranchResolver(service: mock)
        let resolved = try await resolver.resolve(
            selector: .rule(prefix: "test", format: .yyyymmdd),
            gitlabUrl: "https://gitlab.example.com",
            projectPath: "group/svc",
            token: "t"
        )
        XCTAssertNil(resolved)
    }

    func testCustomRegexPicksLexicographicallyLargest() async throws {
        let mock = MockService()
        mock.branches = ["release-2026-03-01", "release-2026-03-15", "release-2025-12-31"]
        let resolver = BranchResolver(service: mock)
        let resolved = try await resolver.resolve(
            selector: .regex("^release-\\d{4}-\\d{2}-\\d{2}$"),
            gitlabUrl: "https://gitlab.example.com",
            projectPath: "group/svc",
            token: "t"
        )
        XCTAssertEqual(resolved, "release-2026-03-15")
        XCTAssertNil(mock.lastSearch ?? nil)  // custom regex passes nil search
    }

    func testRuleWithTailVariant() async throws {
        let mock = MockService()
        mock.branches = ["test-20260326", "test-20260326-hotfix", "test-20260328-staging"]
        let resolver = BranchResolver(service: mock)
        let resolved = try await resolver.resolve(
            selector: .rule(prefix: "test", format: .yyyymmddWithTail),
            gitlabUrl: "https://gitlab.example.com",
            projectPath: "group/svc",
            token: "t"
        )
        // Both *-hotfix and *-staging match; lex-desc → "test-20260328-staging"
        XCTAssertEqual(resolved, "test-20260328-staging")
    }
}
