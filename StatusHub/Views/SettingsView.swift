import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: HubStore
    @Environment(\.dismiss) var dismiss

    @State private var selectedSection: SettingsSection = .general
    @State private var gitlabStep: Int = 1
    @State private var gitlabUrl: String = ""
    @State private var token: String = ""
    @State private var pollInterval: String = "60"
    @State private var selectedRepos: [Repository] = []
    @State private var pluginURL: String = ""

    private var gitLabStore: RepositoryStore { store.gitLabProvider.store }
    private var externalStore: ExternalProviderStore { store.externalProviderStore }
    private var service: GitLabServiceProtocol { GitLabService() }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $selectedSection) {
                ForEach(SettingsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()

            switch selectedSection {
            case .general:
                generalView
            case .gitlab:
                gitLabSettingsView
            case .plugins:
                pluginSettingsView
            }
        }
        .frame(width: 560, height: 620)
        .onAppear { loadCurrentSettings() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.overallStatus.color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("Status Hub 设置")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("管理内置 Provider、外部插件和本地状态源")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var generalView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSummaryRow(
                    title: "整体状态",
                    subtitle: "\(store.overallStatus.label) · \(store.activeCount) 个运行中 · \(store.attentionCount) 个待确认",
                    status: store.overallStatus,
                    icon: "circle.grid.2x2.fill"
                )
                SettingsSummaryRow(
                    title: "Codex 自动化",
                    subtitle: "\(store.automationStore.runs.count) 条运行记录",
                    status: store.automationStore.overallStatus,
                    icon: "bolt.rectangle"
                )
                SettingsSummaryRow(
                    title: "GitLab Pipeline",
                    subtitle: gitLabStore.states.isEmpty ? "未配置监控仓库" : "\(gitLabStore.states.count) 个分支监控",
                    status: store.gitLabProvider.overallStatus,
                    icon: "point.3.connected.trianglepath.dotted"
                )
                SettingsSummaryRow(
                    title: "外部 Provider",
                    subtitle: "\(externalStore.installedPlugins.count) 个插件，\(externalStore.providers.count) 个 Provider",
                    status: externalStore.overallStatus,
                    icon: "square.stack.3d.up"
                )

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("本地目录")
                        .font(.headline)
                    DirectoryRow(
                        title: "外部 Provider 注册",
                        path: "~/Library/Application Support/StatusHub/providers"
                    )
                    DirectoryRow(
                        title: "插件安装目录",
                        path: "~/Library/Application Support/StatusHub/plugins"
                    )
                    DirectoryRow(
                        title: "Codex 自动化记录",
                        path: "~/Library/Application Support/IntelliAutomation/runs"
                    )
                }
            }
            .padding(16)
        }
    }

    private var gitLabSettingsView: some View {
        VStack(spacing: 0) {
            HStack {
                Text(gitlabStep == 1 ? "GitLab 连接" : "GitLab 监控仓库")
                    .font(.headline)
                Spacer()
                Text("\(gitlabStep)/2")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if gitlabStep == 1 {
                gitLabConnectionView
            } else {
                gitLabRepositoryView
            }
        }
    }

    private var gitLabConnectionView: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("https://gitlab.company.com", text: $gitlabUrl)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("GitLab 地址")
                }

                Section {
                    SecureField("glpat-xxxxxxxxxxxxxxxxxxxx", text: $token)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text("需要 read_api 权限")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("?") {
                            let baseUrl = gitlabUrl.isEmpty ? "https://gitlab.com" : gitlabUrl
                            if let url = URL(string: "\(baseUrl)/-/profile/personal_access_tokens") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Access Token")
                }

                Section {
                    HStack {
                        TextField("60", text: $pollInterval)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("秒")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("轮询间隔")
                }
            }
            .formStyle(.grouped)

            Spacer()

            HStack {
                Spacer()
                Button("下一步") {
                    saveConnectionSettings()
                    gitlabStep = 2
                }
                .buttonStyle(.borderedProminent)
                .disabled(gitlabUrl.isEmpty || token.isEmpty)
            }
            .padding()
        }
    }

    private var gitLabRepositoryView: some View {
        VStack(spacing: 0) {
            ProjectSearchView(
                gitlabUrl: gitlabUrl,
                token: token,
                service: service,
                selectedRepos: $selectedRepos
            )

            Divider()

            HStack {
                Button("返回连接") { gitlabStep = 1 }
                    .buttonStyle(.plain)
                Spacer()
                Button("保存 GitLab 配置") { saveGitLabSettings() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private var pluginSettingsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("安装插件")
                    .font(.headline)
                HStack(spacing: 8) {
                    TextField("git@github.com:owner/status-hub-plugin.git", text: $pluginURL)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let url = pluginURL
                        Task {
                            await externalStore.installPlugin(from: url)
                            pluginURL = ""
                        }
                    } label: {
                        if externalStore.isInstalling {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Label("安装", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(externalStore.isInstalling || pluginURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let message = externalStore.installMessage, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(message.hasPrefix("安装失败") ? .red : .secondary)
                }
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if externalStore.installedPlugins.isEmpty {
                        Text("暂无已安装插件")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    } else {
                        ForEach(externalStore.installedPlugins) { plugin in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(plugin.title)
                                        .fontWeight(.medium)
                                    if let version = plugin.version {
                                        Text("v\(version)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("\(plugin.manifest.providers.count) Provider")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(plugin.sourceURL)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    private func loadCurrentSettings() {
        gitlabUrl = gitLabStore.settings.gitlabUrl
        token = KeychainService.loadToken() ?? ""
        pollInterval = "\(gitLabStore.settings.pollInterval)"
        selectedRepos = gitLabStore.settings.repositories
    }

    private func saveConnectionSettings() {
        var settings = gitLabStore.settings
        var cleanUrl = gitlabUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanUrl.hasSuffix("/") { cleanUrl = String(cleanUrl.dropLast()) }
        settings.gitlabUrl = cleanUrl
        settings.pollInterval = max(10, Int(pollInterval) ?? 60)
        gitLabStore.updateSettings(settings)
        KeychainService.saveToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func saveGitLabSettings() {
        saveConnectionSettings()
        var settings = gitLabStore.settings
        settings.repositories = selectedRepos
        gitLabStore.updateSettings(settings)
        gitlabStep = 1
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case gitlab
    case plugins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "总览"
        case .gitlab: return "GitLab"
        case .plugins: return "插件"
        }
    }
}

private struct SettingsSummaryRow: View {
    let title: String
    let subtitle: String
    let status: HubStatus
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(status.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(status.label)
                .font(.caption)
                .foregroundColor(status.color)
        }
    }
}

private struct DirectoryRow: View {
    let title: String
    let path: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                Text(path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: expandedPath(path), isDirectory: true))
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
        }
    }

    private func expandedPath(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.path + String(path.dropFirst())
        }
        return path
    }
}
