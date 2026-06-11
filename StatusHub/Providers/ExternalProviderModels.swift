import Foundation

struct ExternalProviderManifest: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let statusFile: String
    let configFile: String?
    let command: String?
    let arguments: [String]?
    let workingDirectory: String?
    let configuration: [ExternalProviderConfigSection]?

    init(
        id: String,
        title: String,
        icon: String,
        statusFile: String,
        configFile: String? = nil,
        command: String? = nil,
        arguments: [String]? = nil,
        workingDirectory: String? = nil,
        configuration: [ExternalProviderConfigSection]? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.statusFile = statusFile
        self.configFile = configFile
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.configuration = configuration
    }
}

struct ExternalProviderConfigSection: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let fields: [ExternalProviderConfigField]
}

struct ExternalProviderConfigField: Codable, Identifiable, Equatable {
    let key: String
    let title: String
    let type: String
    let placeholder: String?
    let defaultValue: String?
    let help: String?
    let options: [ExternalProviderConfigOption]?
    let command: String?
    let arguments: [String]?
    let workingDirectory: String?

    var id: String { key }
}

struct ExternalProviderConfigOption: Codable, Identifiable, Equatable {
    let value: String
    let title: String

    var id: String { value }
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
    let gitTag: String?

    var id: String { manifest.id }
    var title: String { manifest.title }
    var version: String? { manifest.version }
    var isBuiltin: Bool { sourceURL.hasPrefix("builtin:") }
    var builtinId: String? {
        guard isBuiltin else { return nil }
        return String(sourceURL.dropFirst("builtin:".count))
    }
}

struct PluginUpdateInfo: Equatable {
    let currentTag: String?
    let latestTag: String?
    let isChecking: Bool
    let errorMessage: String?

    var updateAvailable: Bool {
        guard let currentTag, let latestTag else { return false }
        return normalizedVersion(latestTag).localizedStandardCompare(normalizedVersion(currentTag)) == .orderedDescending
    }

    private func normalizedVersion(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }
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
    let value: String?
    let detail: [String: String]?
    let actions: [ExternalProviderAction]?
    let links: [ExternalProviderLink]?
}

struct ExternalProviderAction: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let command: String
    let arguments: [String]?
    let workingDirectory: String?
    let destructive: Bool?
}

struct ExternalProviderLink: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let url: String
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
    var icon: String { manifest.icon }
    var command: String? { manifest.command }
    var configFile: String? { manifest.configFile }
    var configuration: [ExternalProviderConfigSection] { manifest.configuration ?? [] }
}
