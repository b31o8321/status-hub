import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: HubStore
    @Environment(\.dismiss) var dismiss

    @State private var selectedSection: SettingsSection = .general
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
        ExternalProvidersView(store: externalStore)
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
