import Foundation

struct AppSettings: Codable {
    var gitlabUrl: String
    var pollInterval: Int
    var repositories: [Repository]

    static let storageKey = "com.status-hub.gitlab.appSettings"

    static let `default` = AppSettings(
        gitlabUrl: "",
        pollInterval: 60,
        repositories: []
    )

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
