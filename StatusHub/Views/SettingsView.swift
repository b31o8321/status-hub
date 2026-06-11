import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: HubStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: SettingsTab = .overview

    private var externalStore: ExternalProviderStore { store.externalProviderStore }
    private var configurableProviders: [ExternalProviderRuntime] {
        externalStore.providers.filter { !$0.configuration.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()

            switch selectedTab {
            case .overview:
                SettingsOverviewView(store: externalStore)
            case .installed:
                configurationView
            case .marketplace:
                ExternalProvidersView(store: externalStore, fixedTab: .marketplace)
            case .github:
                ExternalProvidersView(store: externalStore, fixedTab: .github)
            }
        }
        .frame(width: 620, height: 680)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .foregroundColor(.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Status Hub 设置")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("管理 Provider 安装、运行和配置")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var configurationView: some View {
        Group {
            if configurableProviders.isEmpty {
                emptyConfigurationView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(configurableProviders) { provider in
                            ProviderConfigurationView(provider: provider, store: externalStore)
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    private var emptyConfigurationView: some View {
        VStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("暂无可配置 Provider")
                .font(.headline)
            Text("安装带配置声明的 Provider 后，这里会显示它自己的设置项。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                selectedTab = .marketplace
            } label: {
                Label("打开市场", systemImage: "shippingbox")
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

private struct SettingsOverviewView: View {
    @ObservedObject var store: ExternalProviderStore

    private var updateCount: Int {
        store.installedPlugins.filter { store.updateInfo(for: $0.id)?.updateAvailable == true }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    OverviewStatCard(title: "Provider", value: "\(store.providers.count)", subtitle: "已安装")
                    OverviewStatCard(title: "插件", value: "\(store.installedPlugins.count)", subtitle: "安装包")
                    OverviewStatCard(title: "更新", value: "\(updateCount)", subtitle: "可更新")
                    OverviewStatCard(title: "状态", value: store.overallStatus.label, subtitle: "整体")
                }

                HStack {
                    Text("Provider 安装状态")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await store.updateAllInstalledPlugins() }
                    } label: {
                        if store.isInstalling {
                            ProgressView().scaleEffect(0.55)
                        } else {
                            Label("全部更新", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(store.isInstalling || store.installedPlugins.isEmpty)
                }

                if let message = store.installMessage, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(message.hasPrefix("安装失败") || message.contains("失败") ? .red : .secondary)
                        .lineLimit(2)
                }

                if store.providers.isEmpty {
                    EmptyProvidersView()
                        .frame(minHeight: 300)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(store.providers) { provider in
                            SettingsProviderOverviewRow(
                                provider: provider,
                                plugin: store.installedPlugin(for: provider),
                                updateInfo: store.updateInfo(for: provider)
                            )
                            Divider()
                        }
                    }
                }
            }
            .padding(18)
        }
        .task {
            await store.refreshPluginUpdates()
        }
    }
}

private struct OverviewStatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SettingsProviderOverviewRow: View {
    let provider: ExternalProviderRuntime
    let plugin: InstalledPlugin?
    let updateInfo: PluginUpdateInfo?

    private var installText: String {
        if plugin?.isBuiltin == true {
            if let version = plugin?.version {
                return "内置 \(version)"
            }
            return "内置"
        }
        if let tag = plugin?.gitTag {
            return "已安装 \(tag)"
        }
        if let version = plugin?.version {
            return "已安装 \(version)"
        }
        return "已安装"
    }

    private var updateText: String {
        if plugin?.isBuiltin == true { return "随 App 更新" }
        guard let updateInfo else { return "未检查" }
        if updateInfo.isChecking { return "检查中" }
        if let error = updateInfo.errorMessage, !error.isEmpty { return "检查失败" }
        if updateInfo.updateAvailable, let latest = updateInfo.latestTag { return "可更新 \(latest)" }
        return "最新"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProviderIconView(
                icon: provider.icon,
                baseDirectory: provider.baseDirectory,
                status: provider.status,
                size: 18
            )
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(provider.title)
                        .fontWeight(.semibold)
                    Text(provider.status.label)
                        .font(.caption)
                        .foregroundColor(provider.status.color)
                }
                Text(provider.snapshot?.summary ?? provider.errorMessage ?? "无状态摘要")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Label(installText, systemImage: "checkmark.circle")
                    Label(updateText, systemImage: updateInfo?.updateAvailable == true ? "arrow.down.circle" : "checkmark.seal")
                }
                .font(.caption2)
                .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Text(provider.baseDirectory.path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([provider.baseDirectory])
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 10)
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case overview
    case installed
    case marketplace
    case github

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "总览"
        case .installed: return "已安装"
        case .marketplace: return "市场"
        case .github: return "GitHub"
        }
    }
}

private struct ProviderConfigurationView: View {
    let provider: ExternalProviderRuntime
    @ObservedObject var store: ExternalProviderStore
    @State private var values: [String: String] = [:]
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    ProviderIconView(
                        icon: provider.icon,
                        baseDirectory: provider.baseDirectory,
                        status: provider.status,
                        size: 18
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Provider 设置")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("固定", isOn: Binding(
                        get: { store.isProviderPinned(provider.id) },
                        set: { store.setProviderPinned(provider.id, pinned: $0) }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(provider.configuration) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        ForEach(section.fields) { field in
                            ConfigurationFieldRow(
                                field: field,
                                provider: provider,
                                store: store,
                                value: Binding(
                                    get: { values[field.key] ?? field.defaultValue ?? "" },
                                    set: { newValue in
                                        guard field.type != "externalConfig" else { return }
                                        values[field.key] = newValue
                                        store.saveConfigurationValue(newValue, field: field, provider: provider)
                                    }
                                )
                            )
                        }
                    }
                    .padding(.leading, 28)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            values = store.configurationValues(for: provider)
        }
    }
}

private struct ConfigurationFieldRow: View {
    let field: ExternalProviderConfigField
    let provider: ExternalProviderRuntime
    @ObservedObject var store: ExternalProviderStore
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Text(field.title)
                    .frame(width: 150, alignment: .leading)
                    .foregroundColor(.primary)
                editor
            }
            if let help = field.help, !help.isEmpty {
                Text(help)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 160)
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch field.type {
        case "externalConfig":
            Button {
                store.runConfigurationAction(field, provider: provider)
            } label: {
                if store.isConfigurationActionRunning(provider: provider, field: field) {
                    ProgressView().scaleEffect(0.55)
                } else {
                    Label(field.placeholder ?? "打开选择器", systemImage: "slider.horizontal.3")
                }
            }
            .disabled(field.command == nil || store.isConfigurationActionRunning(provider: provider, field: field))
        case "toggle":
            Toggle("", isOn: Binding(
                get: { value == "true" },
                set: { value = $0 ? "true" : "false" }
            ))
            .toggleStyle(.switch)
        case "select":
            Picker("", selection: $value) {
                ForEach(field.options ?? []) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
        case "multiselect":
            VStack(alignment: .leading, spacing: 4) {
                ForEach(field.options ?? []) { option in
                    Toggle(option.title, isOn: Binding(
                        get: { selectedValues.contains(option.value) },
                        set: { isOn in
                            var selected = selectedValues
                            if isOn {
                                selected.insert(option.value)
                            } else {
                                selected.remove(option.value)
                            }
                            value = selected.sorted().joined(separator: ",")
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        case "password":
            SecureField(field.placeholder ?? "", text: $value)
                .textFieldStyle(.roundedBorder)
        case "number":
            TextField(field.placeholder ?? "", text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        case "textarea":
            TextEditor(text: $value)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        default:
            TextField(field.placeholder ?? "", text: $value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var selectedValues: Set<String> {
        Set(value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }
}
