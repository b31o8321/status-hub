import XCTest
@testable import StatusHub

final class BranchSelectorTests: XCTestCase {

    // MARK: BranchDateFormat.regex

    func testYYYYMMDDRegex() {
        XCTAssertEqual(BranchDateFormat.yyyymmdd.regex(prefix: "test"), "^test-\\d{8}$")
    }

    func testDashedRegex() {
        XCTAssertEqual(BranchDateFormat.yyyymmddDashed.regex(prefix: "test"), "^test-\\d{4}-\\d{2}-\\d{2}$")
    }

    func testDottedRegex() {
        XCTAssertEqual(BranchDateFormat.yyyymmddDotted.regex(prefix: "test"), "^test-\\d{4}\\.\\d{2}\\.\\d{2}$")
    }

    func testWithTailRegex() {
        XCTAssertEqual(BranchDateFormat.yyyymmddWithTail.regex(prefix: "test"), "^test-\\d{8}-.+$")
    }

    func testPrefixWithRegexSpecialsIsEscaped() {
        // prefix containing dot / plus must not be interpreted as regex
        let pattern = BranchDateFormat.yyyymmdd.regex(prefix: "test.v1+")
        XCTAssertEqual(pattern, "^test\\.v1\\+-\\d{8}$")
    }

    // MARK: BranchSelector codable round trip

    func testFixedRoundTrip() throws {
        try roundTrip(.fixed("staging"))
    }

    func testRuleRoundTrip() throws {
        try roundTrip(.rule(prefix: "test", format: .yyyymmdd))
    }

    func testRegexRoundTrip() throws {
        try roundTrip(.regex("^release-\\d+$"))
    }

    private func roundTrip(_ selector: BranchSelector, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try JSONEncoder().encode(selector)
        let decoded = try JSONDecoder().decode(BranchSelector.self, from: data)
        XCTAssertEqual(selector, decoded, file: file, line: line)
    }

    // MARK: Helpers on BranchSelector

    func testCompiledRegexNilForFixed() {
        XCTAssertNil(BranchSelector.fixed("main").compiledRegex)
    }

    func testCompiledRegexForRule() {
        XCTAssertEqual(BranchSelector.rule(prefix: "test", format: .yyyymmdd).compiledRegex, "^test-\\d{8}$")
    }

    func testSearchPrefixOnlyForRule() {
        XCTAssertNil(BranchSelector.fixed("x").searchPrefix)
        XCTAssertEqual(BranchSelector.rule(prefix: "test", format: .yyyymmdd).searchPrefix, "test")
        XCTAssertNil(BranchSelector.regex(".+").searchPrefix)
    }

    // MARK: Repository legacy decoding (migrates older fields to `branches`)

    func testRepositoryDecodesOldestLegacyBranchField() throws {
        // Pre-v0.1.0: `branch: "staging"`
        let json = """
        {"id":"\(UUID().uuidString)","name":"svc","projectPath":"group/svc","branch":"staging"}
        """.data(using: .utf8)!
        let repo = try JSONDecoder().decode(Repository.self, from: json)
        XCTAssertEqual(repo.branches.count, 1)
        XCTAssertEqual(repo.branches.first?.selector, .fixed("staging"))
    }

    func testRepositoryDecodesV01LegacySingleSelector() throws {
        // v0.1.0 – v0.1.9: single `branchSelector`
        let json = """
        {
          "id":"\(UUID().uuidString)",
          "name":"svc",
          "projectPath":"group/svc",
          "branchSelector":{"type":"rule","prefix":"test","format":"yyyymmdd"}
        }
        """.data(using: .utf8)!
        let repo = try JSONDecoder().decode(Repository.self, from: json)
        XCTAssertEqual(repo.branches.count, 1)
        XCTAssertEqual(repo.branches.first?.selector, .rule(prefix: "test", format: .yyyymmdd))
    }

    func testRepositoryDecodesNewBranchesArray() throws {
        // v0.1.10+: `branches: [{ id, selector }]`
        let branchId = UUID()
        let json = """
        {
          "id":"\(UUID().uuidString)",
          "name":"svc",
          "projectPath":"group/svc",
          "branches":[
            {"id":"\(branchId.uuidString)","selector":{"type":"fixed","value":"main"}},
            {"id":"\(UUID().uuidString)","selector":{"type":"rule","prefix":"staging","format":"yyyymmdd"}}
          ]
        }
        """.data(using: .utf8)!
        let repo = try JSONDecoder().decode(Repository.self, from: json)
        XCTAssertEqual(repo.branches.count, 2)
        XCTAssertEqual(repo.branches[0].id, branchId)
        XCTAssertEqual(repo.branches[0].selector, .fixed("main"))
        XCTAssertEqual(repo.branches[1].selector, .rule(prefix: "staging", format: .yyyymmdd))
    }

    func testRepositoryRoundTripWritesNewFormat() throws {
        let repo = Repository(name: "svc", projectPath: "group/svc", branchSelector: .rule(prefix: "test", format: .yyyymmdd))
        let data = try JSONEncoder().encode(repo)
        let decoded = try JSONDecoder().decode(Repository.self, from: data)
        XCTAssertEqual(decoded, repo)
        // Ensure new format keys are present and legacy keys are not written back.
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(dict?["branch"])
        XCTAssertNil(dict?["branchSelector"])
        XCTAssertNotNil(dict?["branches"])
    }
}
