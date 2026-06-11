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
            case .automation:
                AutomationRunsView(store: store.automationStore)
            case .gitlab:
                GitLabProviderView(store: store.gitLabProvider.store)
            case .external:
                ExternalProvidersView(store: store.externalProviderStore)
            case .all:
                OverviewView(store: store)
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
        var parts = [store.overallStatus.label]
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
    case automation
    case gitlab
    case external

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "总览"
        case .automation: return "自动化"
        case .gitlab: return "GitLab"
        case .external: return "外部"
        }
    }
}

private struct OverviewView: View {
    @ObservedObject var store: HubStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ProviderSummaryRow(
                    title: "Codex 自动化",
                    subtitle: automationSubtitle,
                    status: store.automationStore.overallStatus,
                    icon: "bolt.rectangle"
                )
                ProviderSummaryRow(
                    title: "GitLab Pipeline",
                    subtitle: gitLabSubtitle,
                    status: store.gitLabProvider.overallStatus,
                    icon: "point.3.connected.trianglepath.dotted"
                )
                ProviderSummaryRow(
                    title: "外部 Provider",
                    subtitle: externalSubtitle,
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
            .padding(12)
        }
    }

    private var automationSubtitle: String {
        let total = store.automationStore.runs.count
        let active = store.automationStore.activeRuns.count
        if total == 0 { return "暂无本地自动化运行记录" }
        if active > 0 { return "\(active) 个运行中，最近 \(total) 条记录" }
        return "最近 \(total) 条记录"
    }

    private var gitLabSubtitle: String {
        let total = store.gitLabProvider.store.states.count
        if total == 0 { return "未配置监控仓库" }
        return "\(total) 个分支监控"
    }

    private var externalSubtitle: String {
        let total = store.externalProviderStore.providers.count
        if total == 0 { return "暂无外部程序注册" }
        return "\(total) 个外部 Provider"
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
