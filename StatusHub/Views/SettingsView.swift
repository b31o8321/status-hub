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
                ExternalProvidersView(store: externalStore, fixedTab: .installed)
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
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(configurableProviders) { provider in
                            ProviderConfigurationView(provider: provider, store: externalStore)
                            Divider()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: provider.icon)
                    .frame(width: 18)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.title)
                        .font(.headline)
                    Text("Provider 设置")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("一级展示", isOn: Binding(
                    get: { store.isProviderPinned(provider.id) },
                    set: { store.setProviderPinned(provider.id, pinned: $0) }
                ))
                .toggleStyle(.checkbox)
            }

            ForEach(provider.configuration) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    ForEach(section.fields) { field in
                        ConfigurationFieldRow(
                            field: field,
                            value: Binding(
                                get: { values[field.key] ?? field.defaultValue ?? "" },
                                set: { newValue in
                                    values[field.key] = newValue
                                    store.saveConfigurationValue(newValue, field: field, provider: provider)
                                }
                            )
                        )
                    }
                }
            }
        }
        .onAppear {
            values = store.configurationValues(for: provider)
        }
    }
}

private struct ConfigurationFieldRow: View {
    let field: ExternalProviderConfigField
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
        default:
            TextField(field.placeholder ?? "", text: $value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var selectedValues: Set<String> {
        Set(value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }
}
