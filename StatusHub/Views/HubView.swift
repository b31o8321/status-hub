import SwiftUI
import AppKit

extension Notification.Name {
    static let openSettings = Notification.Name("com.status-hub.openSettings")
    static let refreshRequested = Notification.Name("com.status-hub.refreshRequested")
    static let closePopoverRequested = Notification.Name("com.status-hub.closePopoverRequested")
}

struct HubView: View {
    @ObservedObject var store: HubStore
    @State private var selectedTab: HubTab = .all

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $selectedTab) {
                ForEach(HubTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case .all:
                OverviewView(store: store)
            case .providers:
                ExternalProvidersView(store: store.externalProviderStore)
            }
        }
        .frame(width: 380, height: 520)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.overallStatus.color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Status Hub")
                        .fontWeight(.semibold)
                    Text("v\(appVersion)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(headerSubtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: {
                NotificationCenter.default.post(name: .refreshRequested, object: nil)
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("刷新")

            Button(action: {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("设置")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var headerSubtitle: String {
        var parts = [store.statusLabel]
        if store.activeCount > 0 {
            parts.append("\(store.activeCount) 个运行中")
        }
        if store.attentionCount > 0 {
            parts.append("\(store.attentionCount) 个待确认")
        }
        return parts.joined(separator: " · ")
    }
}

private enum HubTab: String, CaseIterable, Identifiable {
    case all
    case providers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "总览"
        case .providers: return "插件"
        }
    }
}

private struct OverviewView: View {
    @ObservedObject var store: HubStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.providerCount == 0 {
                    EmptyHubView()
                } else {
                    ProviderSummaryRow(
                        title: "Provider",
                        subtitle: "\(store.pluginCount) 个插件，\(store.providerCount) 个 Provider",
                        status: store.externalProviderStore.overallStatus,
                        icon: "square.stack.3d.up"
                    )

                    ForEach(store.externalProviderStore.providers) { provider in
                        ProviderSummaryRow(
                            title: provider.title,
                            subtitle: provider.snapshot?.summary ?? provider.errorMessage ?? "无状态摘要",
                            status: provider.status,
                            icon: provider.icon
                        )
                    }
                }
            }
            .padding(12)
        }
    }
}

private struct EmptyHubView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("暂无 Provider")
                .font(.headline)
            Text("从插件页安装 Provider 后，这里会显示状态总览。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(20)
    }
}

private struct ProviderSummaryRow: View {
    let title: String
    let subtitle: String
    let status: HubStatus
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundColor(status.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(status.label)
                .font(.caption)
                .foregroundColor(status.color)
        }
    }
}
