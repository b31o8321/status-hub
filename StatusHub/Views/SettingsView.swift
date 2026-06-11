import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: HubStore
    @Environment(\.dismiss) var dismiss

    @State private var selectedSection: SettingsSection = .general
    @State private var pluginURL = ""

    private var externalStore: ExternalProviderStore { store.externalProviderStore }

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
            case .plugins:
                pluginSettingsView
            }
        }
        .frame(width: 560, height: 620)
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
                Text("管理插件和外部 Provider")
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
                    subtitle: "\(store.statusLabel) · \(store.activeCount) 个运行中 · \(store.attentionCount) 个待确认",
                    status: store.overallStatus,
                    statusLabel: store.statusLabel,
                    icon: "circle.grid.2x2.fill"
                )
                SettingsSummaryRow(
                    title: "Provider",
                    subtitle: "\(store.pluginCount) 个插件，\(store.providerCount) 个 Provider",
                    status: externalStore.overallStatus,
                    statusLabel: store.providerCount == 0 ? "未配置" : externalStore.overallStatus.label,
                    icon: "square.stack.3d.up"
                )

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("本地目录")
                        .font(.headline)
                    DirectoryRow(
                        title: "本地 Provider 注册",
                        path: "~/Library/Application Support/StatusHub/providers"
                    )
                    DirectoryRow(
                        title: "插件安装目录",
                        path: "~/Library/Application Support/StatusHub/plugins"
                    )
                }
            }
            .padding(16)
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
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case plugins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "总览"
        case .plugins: return "插件"
        }
    }
}

private struct SettingsSummaryRow: View {
    let title: String
    let subtitle: String
    let status: HubStatus
    var statusLabel: String? = nil
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
            Text(statusLabel ?? status.label)
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
