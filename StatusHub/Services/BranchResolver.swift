import Foundation

struct BranchResolver {
    let service: GitLabServiceProtocol

    /// Resolve a `BranchSelector` to a concrete branch name.
    /// - Returns: a branch name on success, `nil` if rule/regex matched no branch.
    func resolve(
        selector: BranchSelector,
        gitlabUrl: String,
        projectPath: String,
        token: String
    ) async throws -> String? {
        switch selector {
        case .fixed(let name):
            return name

        case .rule, .regex:
            guard let pattern = selector.compiledRegex else { return nil }
            let regex = try NSRegularExpression(pattern: pattern)

            let searchTerm = selector.searchPrefix.map { "^\($0)-" }
            let branches = try await service.fetchBranches(
                gitlabUrl: gitlabUrl,
                token: token,
                projectPath: projectPath,
                search: searchTerm
            )

            let matched = branches
                .map(\.name)
                .filter { name in
                    let range = NSRange(name.startIndex..<name.endIndex, in: name)
                    return regex.firstMatch(in: name, range: range) != nil
                }
                .sorted(by: >)

            return matched.first
        }
    }
}
