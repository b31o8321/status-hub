import Foundation

struct GitLabProject: Identifiable, Decodable {
    let id: Int
    let name: String
    let pathWithNamespace: String
    let defaultBranch: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case pathWithNamespace = "path_with_namespace"
        case defaultBranch = "default_branch"
    }
}
