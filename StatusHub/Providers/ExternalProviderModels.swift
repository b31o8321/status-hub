import Foundation

struct ExternalProviderManifest: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String?
    let statusFile: String
    let command: String?
    let arguments: [String]?
    let workingDirectory: String?

    init(
        id: String,
        title: String,
        icon: String?,
        statusFile: String,
        command: String? = nil,
        arguments: [String]? = nil,
        workingDirectory: String? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.statusFile = statusFile
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

struct StatusHubPluginManifest: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let version: String?
    let providers: [ExternalProviderManifest]
}

struct InstalledPlugin: Identifiable, Equatable {
    let manifest: StatusHubPluginManifest
    let sourceURL: String
    let directory: URL

    var id: String { manifest.id }
    var title: String { manifest.title }
    var version: String? { manifest.version }
}

struct ExternalProviderSnapshot: Codable, Equatable {
    let status: HubStatus
    let summary: String?
    let updatedAt: Date?
    let items: [ExternalProviderItem]
}

struct ExternalProviderItem: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let status: HubStatus?
    let url: String?
}

struct ExternalProviderRuntime: Identifiable, Equatable {
    let manifest: ExternalProviderManifest
    let baseDirectory: URL
    let snapshot: ExternalProviderSnapshot?
    let errorMessage: String?

    var id: String { manifest.id }

    var status: HubStatus {
        if errorMessage != nil { return .failed }
        return snapshot?.status ?? .unknown
    }

    var title: String { manifest.title }
    var icon: String { manifest.icon ?? "square.stack.3d.up" }
    var command: String? { manifest.command }
}
