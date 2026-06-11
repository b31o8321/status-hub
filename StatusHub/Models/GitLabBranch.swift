import Foundation

struct GitLabBranch: Identifiable, Decodable {
    var id: String { name }
    let name: String
}
