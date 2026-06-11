import Foundation

@MainActor
final class ExternalProviderStore: ObservableObject, StatusProvider {
    let providerId = "external-providers"
    let providerTitle = "外部 Provider"
    let providerIcon = "square.stack.3d.up"

    @Published private(set) var providers: [ExternalProviderRuntime] = []
    @Published private(set) var installedPlugins: [InstalledPlugin] = []
    @Published var errorMessage: String?
    @Published var installMessage: String?
    @Published var isInstalling = false

    private let providerDirectory: URL
    private let pluginsDirectory: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private var timer: Timer?
    private var processes: [String: Process] = [:]

    init(
        fileManager: FileManager = .default,
        providerDirectory: URL = ExternalProviderStore.defaultProviderDirectory(),
        pluginsDirectory: URL = ExternalProviderStore.defaultPluginsDirectory()
    ) {
        self.fileManager = fileManager
        self.providerDirectory = providerDirectory
        self.pluginsDirectory = pluginsDirectory
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    nonisolated static func defaultProviderDirectory() -> URL {
        defaultBaseDirectory().appendingPathComponent("providers", isDirectory: true)
    }

    nonisolated static func defaultPluginsDirectory() -> URL {
        defaultBaseDirectory().appendingPathComponent("plugins", isDirectory: true)
    }

    nonisolated private static func defaultBaseDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("StatusHub", isDirectory: true)
    }

    var overallStatus: HubStatus {
        providers.map(\.status).max() ?? .idle
    }

    var activeCount: Int {
        providers.filter { $0.status == .running }.count
    }

    var attentionCount: Int {
        providers.filter { $0.status == .attention }.count
    }

    func start() {
        reload()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func refresh() async {
        reload()
    }

    func reload() {
        do {
            try fileManager.createDirectory(at: providerDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)

            installedPlugins = loadInstalledPlugins()
            let loaded = loadLocalProviders() + installedPlugins.flatMap(loadProviders)
            providers = loaded.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            startManagedCommands(for: providers)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            providers = []
        }
    }

    func installPlugin(from sourceURL: String) async {
        let source = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }

        isInstalling = true
        installMessage = "正在安装 \(source)"
        defer { isInstalling = false }

        do {
            try fileManager.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
            let target = pluginsDirectory.appendingPathComponent(pluginDirectoryName(for: source), isDirectory: true)

            if fileManager.fileExists(atPath: target.path) {
                let manifestURL = target.appendingPathComponent("statushub-plugin.json")
                if fileManager.fileExists(atPath: manifestURL.path) {
                    try await runGit(arguments: ["-C", target.path, "pull", "--ff-only"])
                } else {
                    try fileManager.removeItem(at: target)
                    try await clonePlugin(from: source, to: target)
                }
            } else {
                try await clonePlugin(from: source, to: target)
            }

            let manifestURL = target.appendingPathComponent("statushub-plugin.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                throw PluginInstallError.missingManifest
            }

            reload()
            installMessage = "已安装 \(source)"
        } catch {
            installMessage = "安装失败：\(error.localizedDescription)"
        }
    }

    private func loadLocalProviders() -> [ExternalProviderRuntime] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: providerDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap(loadProvider)
    }

    private func loadProvider(from manifestUrl: URL) -> ExternalProviderRuntime? {
        do {
            let manifestData = try Data(contentsOf: manifestUrl)
            let manifest = try decoder.decode(ExternalProviderManifest.self, from: manifestData)
            return loadRuntime(for: manifest, baseDirectory: manifestUrl.deletingLastPathComponent())
        } catch {
            let fallback = ExternalProviderManifest(
                id: manifestUrl.deletingPathExtension().lastPathComponent,
                title: manifestUrl.lastPathComponent,
                icon: "exclamationmark.triangle",
                statusFile: ""
            )
            return ExternalProviderRuntime(
                manifest: fallback,
                baseDirectory: manifestUrl.deletingLastPathComponent(),
                snapshot: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func loadInstalledPlugins() -> [InstalledPlugin] {
        guard let pluginDirs = try? fileManager.contentsOfDirectory(
            at: pluginsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return pluginDirs.compactMap { directory in
            let manifestURL = directory.appendingPathComponent("statushub-plugin.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(StatusHubPluginManifest.self, from: data) else {
                return nil
            }
            return InstalledPlugin(
                manifest: manifest,
                sourceURL: readGitOrigin(from: directory) ?? directory.path,
                directory: directory
            )
        }.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func loadProviders(from plugin: InstalledPlugin) -> [ExternalProviderRuntime] {
        plugin.manifest.providers.map { provider in
            loadRuntime(for: namespacedProvider(provider, pluginId: plugin.id), baseDirectory: plugin.directory)
        }
    }

    private func namespacedProvider(_ provider: ExternalProviderManifest, pluginId: String) -> ExternalProviderManifest {
        let namespacedId = provider.id.hasPrefix("\(pluginId).") ? provider.id : "\(pluginId).\(provider.id)"
        return ExternalProviderManifest(
            id: namespacedId,
            title: provider.title,
            icon: provider.icon,
            statusFile: provider.statusFile,
            command: provider.command,
            arguments: provider.arguments,
            workingDirectory: provider.workingDirectory
        )
    }

    private func loadRuntime(for manifest: ExternalProviderManifest, baseDirectory: URL) -> ExternalProviderRuntime {
        let statusUrl = expandPath(manifest.statusFile, baseDirectory: baseDirectory)
        do {
            let statusData = try Data(contentsOf: statusUrl)
            let snapshot = try decoder.decode(ExternalProviderSnapshot.self, from: statusData)
            return ExternalProviderRuntime(manifest: manifest, baseDirectory: baseDirectory, snapshot: snapshot, errorMessage: nil)
        } catch {
            return ExternalProviderRuntime(
                manifest: manifest,
                baseDirectory: baseDirectory,
                snapshot: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func startManagedCommands(for providers: [ExternalProviderRuntime]) {
        let currentIds = Set(providers.map(\.id))
        for (id, process) in processes where !currentIds.contains(id) {
            process.terminate()
            processes.removeValue(forKey: id)
        }

        for provider in providers {
            guard provider.command != nil else { continue }
            if let existing = processes[provider.id], existing.isRunning { continue }
            startCommand(for: provider)
        }
    }

    private func startCommand(for provider: ExternalProviderRuntime) {
        guard let command = provider.command else { return }
        let commandURL = expandPath(command, baseDirectory: provider.baseDirectory)
        let workingDirectory = provider.manifest.workingDirectory
            .map { expandPath($0, baseDirectory: provider.baseDirectory) }
            ?? provider.baseDirectory

        let process = Process()
        process.executableURL = commandURL
        process.arguments = provider.manifest.arguments ?? []
        process.currentDirectoryURL = workingDirectory
        process.environment = ProcessInfo.processInfo.environment.merging([
            "STATUS_HUB_PROVIDER_ID": provider.id,
            "STATUS_HUB_STATUS_FILE": expandPath(provider.manifest.statusFile, baseDirectory: provider.baseDirectory).path
        ]) { _, new in new }

        do {
            try process.run()
            processes[provider.id] = process
        } catch {
            errorMessage = "启动 \(provider.title) 失败：\(error.localizedDescription)"
        }
    }

    private func expandPath(_ path: String, baseDirectory: URL) -> URL {
        if path.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return URL(fileURLWithPath: home + String(path.dropFirst()))
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return baseDirectory.appendingPathComponent(path)
    }

    private func pluginDirectoryName(for sourceURL: String) -> String {
        let rawName = URL(string: sourceURL)?.deletingPathExtension().lastPathComponent
            ?? sourceURL.split(separator: "/").last.map(String.init)
            ?? "plugin"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return rawName.unicodeScalars.map { allowed.contains($0) ? String(Character($0)) : "-" }.joined()
    }

    private func clonePlugin(from source: String, to target: URL) async throws {
        do {
            try await runGit(arguments: ["clone", "--depth", "1", source, target.path])
        } catch {
            guard let fallback = githubSSHURL(for: source), fallback != source else {
                throw error
            }
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try await runGit(arguments: ["clone", "--depth", "1", fallback, target.path])
        }
    }

    private func githubSSHURL(for source: String) -> String? {
        guard let components = URLComponents(string: source),
              components.scheme == "https",
              components.host == "github.com" else {
            return nil
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        return "git@github.com:\(path)"
    }

    private func runGit(arguments: [String], timeoutSeconds: TimeInterval = 45) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.environment = ProcessInfo.processInfo.environment.merging([
                "GIT_TERMINAL_PROMPT": "0",
                "GIT_SSH_COMMAND": "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
            ]) { _, new in new }

            let state = GitRunState(continuation: continuation)

            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    state.finish(.success(()))
                } else {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? "git failed"
                    state.finish(.failure(PluginInstallError.gitFailed(output)))
                }
            }
            do {
                try process.run()
                let command = (["git"] + arguments).joined(separator: " ")
                let task = DispatchWorkItem {
                    guard process.isRunning else { return }
                    process.terminate()
                    state.finish(.failure(PluginInstallError.gitTimedOut(command)))
                }
                state.timeoutTask = task
                DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: task)
            } catch {
                state.finish(.failure(error))
            }
        }
    }

    private func readGitOrigin(from directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path, "remote", "get-url", "origin"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class GitRunState {
    private let lock = NSLock()
    private var didFinish = false
    private let continuation: CheckedContinuation<Void, Error>
    var timeoutTask: DispatchWorkItem?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        if didFinish {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()

        timeoutTask?.cancel()
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private enum PluginInstallError: LocalizedError {
    case missingManifest
    case gitFailed(String)
    case gitTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "插件仓库缺少 statushub-plugin.json"
        case .gitFailed(let output):
            return output
        case .gitTimedOut(let command):
            return "Git 命令超时：\(command)"
        }
    }
}
