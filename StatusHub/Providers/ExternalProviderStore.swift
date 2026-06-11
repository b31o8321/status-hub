import Foundation

@MainActor
final class ExternalProviderStore: ObservableObject, StatusProvider {
    let providerId = "external-providers"
    let providerTitle = "外部 Provider"
    let providerIcon = "square.stack.3d.up"

    @Published private(set) var providers: [ExternalProviderRuntime] = []
    @Published private(set) var installedPlugins: [InstalledPlugin] = []
    @Published private(set) var pluginUpdates: [String: PluginUpdateInfo] = [:]
    @Published private(set) var pinnedProviderIds: Set<String>
    @Published private(set) var runningActionIds: Set<String> = []
    @Published var errorMessage: String?
    @Published var installMessage: String?
    @Published var isInstalling = false

    private let providerDirectory: URL
    private let pluginsDirectory: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private var timer: Timer?
    private var processes: [String: Process] = [:]
    private let pinnedProviderIdsKey = "ExternalProviderStore.pinnedProviderIds"

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
        self.pinnedProviderIds = Set(UserDefaults.standard.stringArray(forKey: pinnedProviderIdsKey) ?? [])
    }

    nonisolated static func defaultProviderDirectory() -> URL {
        defaultBaseDirectory().appendingPathComponent("providers", isDirectory: true)
    }

    nonisolated static func defaultPluginsDirectory() -> URL {
        defaultBaseDirectory().appendingPathComponent("plugins", isDirectory: true)
    }

    nonisolated static func defaultBuiltinPluginsDirectory() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("BuiltinPlugins", isDirectory: true)
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

    var pinnedProviders: [ExternalProviderRuntime] {
        providers.filter { pinnedProviderIds.contains($0.id) }
    }

    func isProviderPinned(_ providerId: String) -> Bool {
        pinnedProviderIds.contains(providerId)
    }

    func setProviderPinned(_ providerId: String, pinned: Bool) {
        if pinned {
            pinnedProviderIds.insert(providerId)
        } else {
            pinnedProviderIds.remove(providerId)
        }
        UserDefaults.standard.set(Array(pinnedProviderIds).sorted(), forKey: pinnedProviderIdsKey)
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
            let preservedRuntime = try preserveRuntimeDirectory(for: target)

            if fileManager.fileExists(atPath: target.path) {
                let manifestURL = target.appendingPathComponent("statushub-plugin.json")
                if fileManager.fileExists(atPath: manifestURL.path) {
                    try await fetchAndCheckoutLatestTag(in: target)
                } else {
                    try fileManager.removeItem(at: target)
                    try await clonePlugin(from: source, to: target)
                }
            } else {
                try await clonePlugin(from: source, to: target)
            }
            try restoreRuntimeDirectory(preservedRuntime, to: target)

            let manifestURL = target.appendingPathComponent("statushub-plugin.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                throw PluginInstallError.missingManifest
            }

            reload()
            await refreshPluginUpdates()
            installMessage = "已安装 \(source)"
        } catch {
            installMessage = "安装失败：\(error.localizedDescription)"
        }
    }

    func installBuiltinPlugin(id builtinId: String) async {
        isInstalling = true
        installMessage = "正在启用 \(builtinId)"
        defer { isInstalling = false }

        do {
            try installBuiltinPluginContents(id: builtinId)
            reload()
            await refreshPluginUpdates()
            installMessage = "已启用 \(builtinId)"
        } catch {
            installMessage = "启用失败：\(error.localizedDescription)"
        }
    }

    func refreshPluginUpdates() async {
        let plugins = installedPlugins
        guard !plugins.isEmpty else {
            pluginUpdates = [:]
            return
        }

        for plugin in plugins {
            if plugin.isBuiltin {
                pluginUpdates[plugin.id] = PluginUpdateInfo(
                    currentTag: plugin.version,
                    latestTag: plugin.version,
                    isChecking: false,
                    errorMessage: nil
                )
                continue
            }
            pluginUpdates[plugin.id] = PluginUpdateInfo(
                currentTag: plugin.gitTag,
                latestTag: pluginUpdates[plugin.id]?.latestTag,
                isChecking: true,
                errorMessage: nil
            )
        }

        for plugin in plugins {
            if plugin.isBuiltin { continue }
            do {
                let latestTag = try await latestRemoteTag(for: plugin.sourceURL)
                pluginUpdates[plugin.id] = PluginUpdateInfo(
                    currentTag: plugin.gitTag,
                    latestTag: latestTag,
                    isChecking: false,
                    errorMessage: nil
                )
            } catch {
                pluginUpdates[plugin.id] = PluginUpdateInfo(
                    currentTag: plugin.gitTag,
                    latestTag: nil,
                    isChecking: false,
                    errorMessage: error.localizedDescription
                )
            }
        }
    }

    func updateInfo(for pluginId: String) -> PluginUpdateInfo? {
        pluginUpdates[pluginId]
    }

    func installedPlugin(for provider: ExternalProviderRuntime) -> InstalledPlugin? {
        installedPlugins.first { plugin in
            provider.id == plugin.id || provider.id.hasPrefix("\(plugin.id).")
        }
    }

    func updateInfo(for provider: ExternalProviderRuntime) -> PluginUpdateInfo? {
        guard let plugin = installedPlugin(for: provider) else { return nil }
        return updateInfo(for: plugin.id)
    }

    func updateAllInstalledPlugins() async {
        let plugins = installedPlugins
        guard !plugins.isEmpty else { return }

        isInstalling = true
        installMessage = "正在更新全部 Provider"
        defer { isInstalling = false }

        var failures: [String] = []
        for plugin in plugins {
            do {
                if let builtinId = plugin.builtinId {
                    try installBuiltinPluginContents(id: builtinId, preferredTarget: plugin.directory)
                } else {
                    let preservedRuntime = try preserveRuntimeDirectory(for: plugin.directory)
                    try await fetchAndCheckoutLatestTag(in: plugin.directory)
                    try restoreRuntimeDirectory(preservedRuntime, to: plugin.directory)
                }
            } catch {
                failures.append("\(plugin.title)：\(error.localizedDescription)")
            }
        }

        reload()
        await refreshPluginUpdates()
        installMessage = failures.isEmpty ? "已更新全部 Provider" : "部分更新失败：\(failures.joined(separator: "；"))"
    }

    func actionKey(provider: ExternalProviderRuntime, item: ExternalProviderItem, action: ExternalProviderAction) -> String {
        "\(provider.id):\(item.id):\(action.id)"
    }

    func isActionRunning(provider: ExternalProviderRuntime, item: ExternalProviderItem, action: ExternalProviderAction) -> Bool {
        runningActionIds.contains(actionKey(provider: provider, item: item, action: action))
    }

    func runAction(_ action: ExternalProviderAction, for item: ExternalProviderItem, provider: ExternalProviderRuntime) {
        let key = actionKey(provider: provider, item: item, action: action)
        guard !runningActionIds.contains(key) else { return }

        let commandURL = expandPath(action.command, baseDirectory: provider.baseDirectory)
        let workingDirectory = action.workingDirectory
            .map { expandPath($0, baseDirectory: provider.baseDirectory) }
            ?? provider.baseDirectory
        let environment = ProcessInfo.processInfo.environment.merging([
            "STATUS_HUB_PROVIDER_ID": provider.id,
            "STATUS_HUB_ITEM_ID": item.id,
            "STATUS_HUB_ACTION_ID": action.id,
            "STATUS_HUB_ACTION_TITLE": action.title,
            "STATUS_HUB_DATA_DIR": provider.baseDirectory
                .appendingPathComponent("runtime", isDirectory: true)
                .path
        ]) { _, new in new }
        let actionEnvironment: [String: String]
        if let configURL = configURL(for: provider) {
            actionEnvironment = environment.merging(["STATUS_HUB_CONFIG_FILE": configURL.path]) { _, new in new }
        } else {
            actionEnvironment = environment
        }

        runningActionIds.insert(key)
        Task {
            do {
                try await Self.runProcess(
                    executableURL: commandURL,
                    arguments: action.arguments ?? [],
                    workingDirectory: workingDirectory,
                    environment: actionEnvironment
                )
                await MainActor.run {
                    self.errorMessage = nil
                    self.reload()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "执行 \(action.title) 失败：\(error.localizedDescription)"
                }
            }
            await MainActor.run {
                self.runningActionIds.remove(key)
                self.reload()
            }
        }
    }

    func configurationValues(for provider: ExternalProviderRuntime) -> [String: String] {
        var values: [String: String] = [:]
        for section in provider.configuration {
            for field in section.fields {
                if let defaultValue = field.defaultValue {
                    values[field.key] = defaultValue
                }
            }
        }
        guard let configURL = configURL(for: provider),
              let object = readJSONObject(from: configURL) else {
            return values
        }
        for section in provider.configuration {
            for field in section.fields {
                if let value = valueString(in: object, keyPath: field.key) {
                    values[field.key] = value
                }
            }
        }
        return values
    }

    func saveConfigurationValue(_ value: String, field: ExternalProviderConfigField, provider: ExternalProviderRuntime) {
        guard let configURL = configURL(for: provider) else { return }
        var object = readJSONObject(from: configURL) ?? [:]
        setValue(parsedConfigValue(value, field: field), in: &object, keyPath: field.key)
        writeJSONObject(object, to: configURL)
        restart(provider)
    }

    func configurationActionKey(provider: ExternalProviderRuntime, field: ExternalProviderConfigField) -> String {
        "\(provider.id):config:\(field.key)"
    }

    func isConfigurationActionRunning(provider: ExternalProviderRuntime, field: ExternalProviderConfigField) -> Bool {
        runningActionIds.contains(configurationActionKey(provider: provider, field: field))
    }

    func runConfigurationAction(_ field: ExternalProviderConfigField, provider: ExternalProviderRuntime) {
        guard let command = field.command else { return }
        let key = configurationActionKey(provider: provider, field: field)
        guard !runningActionIds.contains(key) else { return }

        let commandURL = expandPath(command, baseDirectory: provider.baseDirectory)
        let workingDirectory = field.workingDirectory
            .map { expandPath($0, baseDirectory: provider.baseDirectory) }
            ?? provider.baseDirectory
        var environment = ProcessInfo.processInfo.environment.merging([
            "STATUS_HUB_PROVIDER_ID": provider.id,
            "STATUS_HUB_CONFIG_FIELD": field.key,
            "STATUS_HUB_DATA_DIR": provider.baseDirectory
                .appendingPathComponent("runtime", isDirectory: true)
                .path
        ]) { _, new in new }
        if let configURL = configURL(for: provider) {
            environment["STATUS_HUB_CONFIG_FILE"] = configURL.path
        }

        runningActionIds.insert(key)
        Task {
            do {
                try await Self.runProcess(
                    executableURL: commandURL,
                    arguments: field.arguments ?? [],
                    workingDirectory: workingDirectory,
                    environment: environment
                )
                await MainActor.run {
                    self.errorMessage = nil
                    self.restart(provider)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "执行 \(field.title) 失败：\(error.localizedDescription)"
                }
            }
            await MainActor.run {
                self.runningActionIds.remove(key)
                self.reload()
            }
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
                sourceURL: readPluginSource(from: directory) ?? readGitOrigin(from: directory) ?? directory.path,
                directory: directory,
                gitTag: readCurrentGitTag(from: directory)
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
            configFile: provider.configFile,
            command: provider.command,
            arguments: provider.arguments,
            workingDirectory: provider.workingDirectory,
            configuration: provider.configuration
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
            "STATUS_HUB_STATUS_FILE": expandPath(provider.manifest.statusFile, baseDirectory: provider.baseDirectory).path,
            "STATUS_HUB_DATA_DIR": provider.baseDirectory
                .appendingPathComponent("runtime", isDirectory: true)
                .path
        ]) { _, new in new }
        if let configURL = configURL(for: provider) {
            process.environment?["STATUS_HUB_CONFIG_FILE"] = configURL.path
        }

        do {
            terminateStaleCommand(at: commandURL)
            try process.run()
            processes[provider.id] = process
        } catch {
            errorMessage = "启动 \(provider.title) 失败：\(error.localizedDescription)"
        }
    }

    private func terminateStaleCommand(at commandURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", NSRegularExpression.escapedPattern(for: commandURL.path)]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
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

    private func configURL(for provider: ExternalProviderRuntime) -> URL? {
        guard let configFile = provider.configFile else { return nil }
        return expandPath(configFile, baseDirectory: provider.baseDirectory)
    }

    private func restart(_ provider: ExternalProviderRuntime) {
        if let process = processes[provider.id] {
            process.terminate()
            processes.removeValue(forKey: provider.id)
        }
        startCommand(for: provider)
        reload()
    }

    private func readJSONObject(from url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) {
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: [.atomic])
        } catch {
            errorMessage = "保存配置失败：\(error.localizedDescription)"
        }
    }

    private func valueString(in object: [String: Any], keyPath: String) -> String? {
        guard let value = value(in: object, keyPath: keyPath) else { return nil }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let array = value as? [Any] { return array.map { "\($0)" }.joined(separator: ",") }
        return "\(value)"
    }

    private func value(in object: [String: Any], keyPath: String) -> Any? {
        let parts = keyPath.split(separator: ".").map(String.init)
        var current: Any = object
        for part in parts {
            guard let dict = current as? [String: Any],
                  let next = dict[part] else { return nil }
            current = next
        }
        return current
    }

    private func setValue(_ value: Any, in object: inout [String: Any], keyPath: String) {
        var parts = keyPath.split(separator: ".").map(String.init)
        guard let first = parts.first else { return }
        parts.removeFirst()
        if parts.isEmpty {
            object[first] = value
            return
        }
        var child = object[first] as? [String: Any] ?? [:]
        setValue(value, in: &child, keyPath: parts.joined(separator: "."))
        object[first] = child
    }

    private func parsedConfigValue(_ value: String, field: ExternalProviderConfigField) -> Any {
        switch field.type {
        case "toggle":
            return value == "true"
        case "number":
            return Double(value) ?? 0
        case "multiselect":
            return value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        default:
            return value
        }
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
            _ = try await runGit(arguments: ["clone", "--depth", "1", source, target.path])
            try await fetchAndCheckoutLatestTag(in: target)
        } catch {
            guard let fallback = githubSSHURL(for: source), fallback != source else {
                throw error
            }
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            _ = try await runGit(arguments: ["clone", "--depth", "1", fallback, target.path])
            try await fetchAndCheckoutLatestTag(in: target)
        }
    }

    private func fetchAndCheckoutLatestTag(in target: URL) async throws {
        _ = try await runGit(arguments: ["-C", target.path, "fetch", "--tags", "--force"])
        guard let latestTag = try await latestLocalTag(in: target) else { return }
        _ = try await runGit(arguments: ["-C", target.path, "reset", "--hard", "HEAD"])
        _ = try await runGit(arguments: ["-C", target.path, "clean", "-fd", "-e", "runtime", "-e", "runtime/**"])
        _ = try await runGit(arguments: ["-C", target.path, "checkout", "--force", "--quiet", latestTag])
    }

    private func installBuiltinPluginContents(id builtinId: String, preferredTarget: URL? = nil) throws {
        guard let sourceRoot = Self.defaultBuiltinPluginsDirectory() else {
            throw PluginInstallError.missingBuiltinDirectory
        }
        let source = sourceRoot.appendingPathComponent(builtinId, isDirectory: true)
        guard fileManager.fileExists(atPath: source.appendingPathComponent("statushub-plugin.json").path) else {
            throw PluginInstallError.missingBuiltinPlugin(builtinId)
        }

        try fileManager.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        let target = preferredTarget
            ?? installedPlugins.first { $0.id == builtinId }?.directory
            ?? pluginsDirectory.appendingPathComponent(builtinId, isDirectory: true)
        let preservedRuntime = try preserveRuntimeDirectory(for: target)
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.copyItem(at: source, to: target)
        try restoreRuntimeDirectory(preservedRuntime, to: target)
        try writeBuiltinSourceMetadata(id: builtinId, to: target)
    }

    private func writeBuiltinSourceMetadata(id builtinId: String, to pluginDirectory: URL) throws {
        let object: [String: String] = ["type": "builtin", "id": builtinId]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: pluginDirectory.appendingPathComponent(".statushub-source.json"), options: [.atomic])
    }

    private func preserveRuntimeDirectory(for pluginDirectory: URL) throws -> URL? {
        let runtimeURL = pluginDirectory.appendingPathComponent("runtime", isDirectory: true)
        guard fileManager.fileExists(atPath: runtimeURL.path) else { return nil }
        let backupParent = fileManager.temporaryDirectory
            .appendingPathComponent("statushub-runtime-\(UUID().uuidString)", isDirectory: true)
        let backupURL = backupParent.appendingPathComponent("runtime", isDirectory: true)
        try fileManager.createDirectory(at: backupParent, withIntermediateDirectories: true)
        try fileManager.copyItem(at: runtimeURL, to: backupURL)
        return backupURL
    }

    private func restoreRuntimeDirectory(_ backupURL: URL?, to pluginDirectory: URL) throws {
        guard let backupURL else { return }
        let runtimeURL = pluginDirectory.appendingPathComponent("runtime", isDirectory: true)
        if fileManager.fileExists(atPath: runtimeURL.path) {
            try fileManager.removeItem(at: runtimeURL)
        }
        try fileManager.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try fileManager.copyItem(at: backupURL, to: runtimeURL)
        try? fileManager.removeItem(at: backupURL.deletingLastPathComponent())
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

    private func latestLocalTag(in target: URL) async throws -> String? {
        let output = try await runGit(arguments: ["-C", target.path, "tag", "--list"])
        return latestTag(from: output.split(separator: "\n").map(String.init))
    }

    private func latestRemoteTag(for sourceURL: String) async throws -> String? {
        let output = try await runGit(arguments: ["ls-remote", "--tags", sourceURL], timeoutSeconds: 20)
        let tags = output.split(separator: "\n").compactMap { line -> String? in
            guard let ref = line.split(separator: "\t").last else { return nil }
            let name = String(ref).replacingOccurrences(of: "refs/tags/", with: "")
            return name.hasSuffix("^{}") ? nil : name
        }
        return latestTag(from: tags)
    }

    private func latestTag(from tags: [String]) -> String? {
        tags
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                normalizedVersion(lhs).localizedStandardCompare(normalizedVersion(rhs)) == .orderedAscending
            }
            .last
    }

    private func normalizedVersion(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    private func runGit(arguments: [String], timeoutSeconds: TimeInterval = 45) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
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

            let state = GitRunState(continuation: continuation, pipe: pipe)

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

    private nonisolated static func runProcess(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let state = ProcessRunState(continuation: continuation, pipe: pipe)
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    state.finish(.success(()))
                } else {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? "process failed"
                    state.finish(.failure(PluginInstallError.processFailed(output)))
                }
            }
            do {
                try process.run()
            } catch {
                state.finish(.failure(error))
            }
        }
    }

    private func readPluginSource(from directory: URL) -> String? {
        let sourceURL = directory.appendingPathComponent(".statushub-source.json")
        guard let data = try? Data(contentsOf: sourceURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              object["type"] == "builtin",
              let id = object["id"],
              !id.isEmpty else {
            return nil
        }
        return "builtin:\(id)"
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

    private func readCurrentGitTag(from directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path, "describe", "--tags", "--exact-match"]
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
    private let continuation: CheckedContinuation<String, Error>
    private let pipe: Pipe
    var timeoutTask: DispatchWorkItem?

    init(continuation: CheckedContinuation<String, Error>, pipe: Pipe) {
        self.continuation = continuation
        self.pipe = pipe
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
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private enum PluginInstallError: LocalizedError {
    case missingManifest
    case missingBuiltinDirectory
    case missingBuiltinPlugin(String)
    case gitFailed(String)
    case gitTimedOut(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "插件仓库缺少 statushub-plugin.json"
        case .missingBuiltinDirectory:
            return "App 内未找到内置 Provider 目录"
        case .missingBuiltinPlugin(let id):
            return "App 内未找到内置 Provider：\(id)"
        case .gitFailed(let output):
            return output
        case .gitTimedOut(let command):
            return "Git 命令超时：\(command)"
        case .processFailed(let output):
            return output
        }
    }
}

private final class ProcessRunState {
    private let lock = NSLock()
    private var didFinish = false
    private let continuation: CheckedContinuation<Void, Error>
    private let pipe: Pipe

    init(continuation: CheckedContinuation<Void, Error>, pipe: Pipe) {
        self.continuation = continuation
        self.pipe = pipe
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        if didFinish {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()

        switch result {
        case .success:
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
