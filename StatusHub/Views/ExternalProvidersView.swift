import SwiftUI
import AppKit

struct ExternalProvidersView: View {
    @ObservedObject var store: ExternalProviderStore
    let fixedTab: PluginTab?
    @State private var selectedTab: PluginTab = .installed
    @State private var pluginURL = ""
    @State private var marketplaceSearch = ""

    init(store: ExternalProviderStore, fixedTab: PluginTab? = nil) {
        self.store = store
        self.fixedTab = fixedTab
    }

    private var effectiveTab: PluginTab {
        fixedTab ?? selectedTab
    }

    var body: some View {
        VStack(spacing: 0) {
            if fixedTab == nil {
                Picker("", selection: $selectedTab) {
                    ForEach(PluginTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                Divider()
            }

            switch effectiveTab {
            case .installed:
                installedView
            case .marketplace:
                marketplaceView
            case .github:
                githubInstallView
            }
        }
    }

    private var marketplaceView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索 Provider", text: $marketplaceSearch)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            if filteredMarketplacePlugins.isEmpty {
                EmptySearchView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredMarketplacePlugins) { plugin in
                            MarketplacePluginRow(
                                plugin: plugin,
                                isInstalled: isInstalled(plugin),
                                updateInfo: store.updateInfo(for: plugin.id),
                                isInstalling: store.isInstalling,
                                install: {
                                    Task { await store.installPlugin(from: plugin.repositoryURL) }
                                }
                            )
                            .padding(.horizontal, 12)
                            Divider()
                        }
                    }
                }
            }
        }
        .task {
            await store.refreshPluginUpdates()
        }
    }

    private var installedView: some View {
        Group {
            if store.providers.isEmpty {
                EmptyProvidersView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.providers) { provider in
                            ExternalProviderRow(provider: provider)
                                .padding(.horizontal, 12)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var githubInstallView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("GitHub 插件地址", text: $pluginURL)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let url = pluginURL
                        Task {
                            await store.installPlugin(from: url)
                            pluginURL = ""
                        }
                    } label: {
                        if store.isInstalling {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                    .disabled(store.isInstalling || pluginURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("安装或更新插件")
                }

                if let message = store.installMessage, !message.isEmpty {
                    Text(message)
                        .font(.caption2)
                        .foregroundColor(message.hasPrefix("安装失败") ? .red : .secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Spacer()
        }
    }

    private func isInstalled(_ plugin: MarketplacePlugin) -> Bool {
        store.installedPlugins.contains { installed in
            installed.id == plugin.id || installed.sourceURL == plugin.repositoryURL
        }
    }

    private var filteredMarketplacePlugins: [MarketplacePlugin] {
        let query = marketplaceSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return MarketplacePlugin.catalog }
        return MarketplacePlugin.catalog.filter { plugin in
            plugin.title.localizedCaseInsensitiveContains(query)
                || plugin.subtitle.localizedCaseInsensitiveContains(query)
                || plugin.id.localizedCaseInsensitiveContains(query)
        }
    }
}

enum PluginTab: String, CaseIterable, Identifiable {
    case installed
    case marketplace
    case github

    var id: String { rawValue }

    var title: String {
        switch self {
        case .installed: return "已安装"
        case .marketplace: return "市场"
        case .github: return "GitHub"
        }
    }
}

private struct MarketplacePlugin: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let repositoryURL: String

    static let catalog = [
        MarketplacePlugin(
            id: "mac-system",
            title: "Mac System",
            subtitle: "CPU、内存、网络、电池、磁盘和温度状态",
            icon: "desktopcomputer",
            repositoryURL: "git@github.com:b31o8321/status-hub-mac-system-provider.git"
        )
    ]
}

private struct MarketplacePluginRow: View {
    let plugin: MarketplacePlugin
    let isInstalled: Bool
    let updateInfo: PluginUpdateInfo?
    let isInstalling: Bool
    let install: () -> Void

    private var buttonTitle: String {
        if !isInstalled { return "安装" }
        guard let updateInfo else { return "检查中" }
        if updateInfo.isChecking { return "检查中" }
        if updateInfo.updateAvailable, let latestTag = updateInfo.latestTag {
            return "更新 \(latestTag)"
        }
        return "已安装"
    }

    private var canInstallOrUpdate: Bool {
        if isInstalling { return false }
        if !isInstalled { return true }
        return updateInfo?.updateAvailable == true
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: plugin.icon)
                .frame(width: 18)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.title)
                    .fontWeight(.medium)
                Text(plugin.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                install()
            } label: {
                if isInstalling {
                    ProgressView().scaleEffect(0.5)
                } else {
                    Text(buttonTitle)
                }
            }
            .disabled(!canInstallOrUpdate)
        }
        .padding(.vertical, 9)
    }
}

struct EmptyProvidersView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("暂无外部 Provider")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("~/Library/Application Support/StatusHub/providers")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

private struct EmptySearchView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("没有匹配的 Provider")
                .font(.headline)
            Text("换一个关键词再试。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

private struct ExternalProviderRow: View {
    let provider: ExternalProviderRuntime
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .frame(width: 10)

                ProviderIconView(
                    icon: provider.icon,
                    baseDirectory: provider.baseDirectory,
                    status: provider.status,
                    size: 16
                )
                Text(provider.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(provider.status.label)
                    .font(.caption)
                    .foregroundColor(provider.status.color)
            }

            if let error = provider.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            } else {
                if let summary = provider.snapshot?.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(isExpanded ? 2 : 1)
                }

                if isExpanded {
                    if let updatedAt = provider.snapshot?.updatedAt {
                        Text(relativeFormatter.localizedString(for: updatedAt, relativeTo: Date()))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    ForEach(provider.snapshot?.items ?? []) { item in
                        ExternalProviderItemRow(item: item)
                    }
                }
            }

            if isExpanded && provider.command != nil {
                Text("由 Status Hub 托管运行")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 7)
    }

    private var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }
}

private struct ExternalProviderItemRow: View {
    let item: ExternalProviderItem

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill((item.status ?? .unknown).color)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption)
                    .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let value = item.value, !value.isEmpty {
                Text(value)
                    .font(.caption)
                    .foregroundColor((item.status ?? .unknown).color)
            }
            if let urlString = item.url, let url = URL(string: urlString) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right")
                }
                .buttonStyle(.plain)
                .font(.caption2)
            }
        }
    }
}
