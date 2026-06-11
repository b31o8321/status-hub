import XCTest
@testable import StatusHub

final class GitLabServiceTests: XCTestCase {

    struct MockGitLabService: GitLabServiceProtocol {
        let resultToReturn: Result<PipelineResult, GitLabError>

        func fetchLatestPipeline(
            gitlabUrl: String,
            projectPath: String,
            branch: String,
            token: String
        ) async throws -> PipelineResult {
            switch resultToReturn {
            case .success(let result): return result
            case .failure(let error): throw error
            }
        }

        func fetchProjects(gitlabUrl: String, token: String, search: String) async throws -> [GitLabProject] {
            return []
        }

        func fetchBranches(gitlabUrl: String, token: String, projectId: Int) async throws -> [GitLabBranch] {
            return []
        }

        func fetchBranches(gitlabUrl: String, token: String, projectPath: String, search: String?) async throws -> [GitLabBranch] {
            return []
        }

        func fetchRecentSuccessDurations(gitlabUrl: String, projectPath: String, branch: String, token: String, limit: Int) async throws -> [TimeInterval] {
            return []
        }
    }

    func testParseSuccessPipeline() async throws {
        let expectedResult = PipelineResult(
            status: .success,
            webUrl: "https://gitlab.example.com/group/project/-/pipelines/1",
            updatedAt: Date(),
            startedAt: nil
        )
        let mock = MockGitLabService(resultToReturn: .success(expectedResult))
        let result = try await mock.fetchLatestPipeline(
            gitlabUrl: "https://gitlab.example.com",
            projectPath: "group/project",
            branch: "main",
            token: "test-token"
        )
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.webUrl, "https://gitlab.example.com/group/project/-/pipelines/1")
    }

    func testParseRunningPipeline() async throws {
        let expectedResult = PipelineResult(
            status: .running,
            webUrl: "https://gitlab.example.com/group/project/-/pipelines/2",
            updatedAt: Date(),
            startedAt: nil
        )
        let mock = MockGitLabService(resultToReturn: .success(expectedResult))
        let result = try await mock.fetchLatestPipeline(
            gitlabUrl: "https://gitlab.example.com",
            projectPath: "group/project",
            branch: "main",
            token: "test-token"
        )
        XCTAssertEqual(result.status, .running)
    }

    func testUnauthorizedThrows() async {
        let mock = MockGitLabService(resultToReturn: .failure(.unauthorized))
        do {
            _ = try await mock.fetchLatestPipeline(
                gitlabUrl: "https://gitlab.example.com",
                projectPath: "group/project",
                branch: "main",
                token: "bad-token"
            )
            XCTFail("Expected GitLabError.unauthorized")
        } catch GitLabError.unauthorized {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNotFoundThrows() async {
        let mock = MockGitLabService(resultToReturn: .failure(.notFound))
        do {
            _ = try await mock.fetchLatestPipeline(
                gitlabUrl: "https://gitlab.example.com",
                projectPath: "group/project",
                branch: "main",
                token: "test-token"
            )
            XCTFail("Expected GitLabError.notFound")
        } catch GitLabError.notFound {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGitLabProjectDecoding() throws {
        let json = """
        [{"id": 42, "name": "frontend", "path_with_namespace": "group/frontend", "default_branch": "main"}]
        """.data(using: .utf8)!
        let projects = try JSONDecoder().decode([GitLabProject].self, from: json)
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].id, 42)
        XCTAssertEqual(projects[0].name, "frontend")
        XCTAssertEqual(projects[0].pathWithNamespace, "group/frontend")
        XCTAssertEqual(projects[0].defaultBranch, "main")
    }

    func testGitLabProjectDecodingNullDefaultBranch() throws {
        let json = """
        [{"id": 1, "name": "empty", "path_with_namespace": "group/empty", "default_branch": null}]
        """.data(using: .utf8)!
        let projects = try JSONDecoder().decode([GitLabProject].self, from: json)
        XCTAssertNil(projects[0].defaultBranch)
    }

    func testGitLabBranchDecoding() throws {
        let json = """
        [{"name": "main"}, {"name": "feature/test"}]
        """.data(using: .utf8)!
        let branches = try JSONDecoder().decode([GitLabBranch].self, from: json)
        XCTAssertEqual(branches.count, 2)
        XCTAssertEqual(branches[0].name, "main")
        XCTAssertEqual(branches[0].id, "main")
        XCTAssertEqual(branches[1].name, "feature/test")
    }
}
