import Foundation

/// One branch the user wants to watch inside a `Repository`. Each watch has its
/// own stable `id`, used as the identity key for `RepositoryState` rows so the
/// runtime state survives reordering, additions, and removals.
struct BranchWatch: Identifiable, Equatable, Codable {
    let id: UUID
    var selector: BranchSelector

    init(id: UUID = UUID(), selector: BranchSelector) {
        self.id = id
        self.selector = selector
    }
}

struct Repository: Identifiable, Equatable {
    let id: UUID
    var name: String
    var projectPath: String
    /// One row in the popover per element. v0.1.10+ allows >1 branch per project.
    var branches: [BranchWatch]

    init(id: UUID = UUID(), name: String, projectPath: String, branches: [BranchWatch]) {
        self.id = id
        self.name = name
        self.projectPath = projectPath
        self.branches = branches
    }

    /// Convenience: single branch via selector (preserves call sites from pre-0.1.10).
    init(id: UUID = UUID(), name: String, projectPath: String, branchSelector: BranchSelector) {
        self.init(
            id: id,
            name: name,
            projectPath: projectPath,
            branches: [BranchWatch(selector: branchSelector)]
        )
    }

    /// Convenience: single fixed branch name.
    init(id: UUID = UUID(), name: String, projectPath: String, branch: String) {
        self.init(id: id, name: name, projectPath: projectPath, branchSelector: .fixed(branch))
    }
}

extension Repository: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case projectPath
        case branches          // v0.1.10+ canonical
        case branchSelector    // legacy (one selector per repo)
        case branch            // older legacy ({ branch: "main" })
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(projectPath, forKey: .projectPath)
        try c.encode(branches, forKey: .branches)
        // legacy keys intentionally not emitted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let name = try c.decode(String.self, forKey: .name)
        let projectPath = try c.decode(String.self, forKey: .projectPath)

        // 1. New format: `branches: [BranchWatch]` — used since v0.1.10.
        if let branches = try c.decodeIfPresent([BranchWatch].self, forKey: .branches) {
            self.init(id: id, name: name, projectPath: projectPath, branches: branches)
            return
        }

        // 2. v0.1.0 – v0.1.9: single `branchSelector: BranchSelector`.
        if let legacySelector = try c.decodeIfPresent(BranchSelector.self, forKey: .branchSelector) {
            self.init(id: id, name: name, projectPath: projectPath, branchSelector: legacySelector)
            return
        }

        // 3. Pre-v0.1.0: `{ branch: "main" }`.
        if let legacyBranchName = try c.decodeIfPresent(String.self, forKey: .branch) {
            self.init(id: id, name: name, projectPath: projectPath, branch: legacyBranchName)
            return
        }

        throw DecodingError.dataCorruptedError(
            forKey: .branches,
            in: c,
            debugDescription: "No branches / branchSelector / branch field present on Repository"
        )
    }
}
