import SwiftUI
import AppKit

extension Notification.Name {
    static let openSettings = Notification.Name("com.status-hub.openSettings")
    static let refreshRequested = Notification.Name("com.status-hub.refreshRequested")
    static let closePopoverRequested = Notification.Name("com.status-hub.closePopoverRequested")
}

struct HubView: View {
    @ObservedObject var store: HubStore
    @State private var selectedPage = HubPage.overview

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var pinnedProviders: [ExternalProviderRuntime] {
        store.externalProviderStore.pinnedProviders
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $selectedPage) {
                Text("总览").tag(HubPage.overview)
                ForEach(pinnedProviders) { provider in
                    Text(provider.title).tag(provider.id)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if selectedPage == HubPage.overview {
                OverviewView(store: store)
            } else if let provider = pinnedProviders.first(where: { $0.id == selectedPage }) {
                ProviderDetailView(provider: provider)
            } else {
                OverviewView(store: store)
            }
        }
        .frame(width: 380, height: 520)
        .onChange(of: pinnedProviders.map(\.id)) { ids in
            if selectedPage != HubPage.overview && !ids.contains(selectedPage) {
                selectedPage = HubPage.overview
            }
        }
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

private enum HubPage {
    static let overview = "overview"
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
                            icon: provider.icon,
                            isPinned: store.externalProviderStore.isProviderPinned(provider.id),
                            togglePinned: {
                                let isPinned = store.externalProviderStore.isProviderPinned(provider.id)
                                store.externalProviderStore.setProviderPinned(provider.id, pinned: !isPinned)
                            }
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
    var isPinned: Bool? = nil
    var togglePinned: (() -> Void)? = nil

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
            if let isPinned, let togglePinned {
                Button(action: togglePinned) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .foregroundColor(isPinned ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "取消一级展示" : "在主界面一级展示")
            }
            Text(status.label)
                .font(.caption)
                .foregroundColor(status.color)
        }
    }
}

private struct ProviderDetailView: View {
    let provider: ExternalProviderRuntime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ProviderSummaryRow(
                    title: provider.title,
                    subtitle: provider.snapshot?.summary ?? provider.errorMessage ?? "无状态摘要",
                    status: provider.status,
                    icon: provider.icon
                )

                if let error = provider.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                ForEach(provider.snapshot?.items ?? []) { item in
                    ProviderItemCard(item: item)
                }
            }
            .padding(12)
        }
    }
}

private struct ProviderItemCard: View {
    let item: ExternalProviderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle()
                    .fill((item.status ?? .unknown).color)
                    .frame(width: 7, height: 7)
                Text(item.title)
                    .fontWeight(.medium)
                Spacer()
                if let value = item.value {
                    Text(value)
                        .font(.caption)
                        .foregroundColor((item.status ?? .unknown).color)
                }
            }
            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            if let detail = item.detail, !detail.isEmpty {
                Text(detailSummary(detail))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    private func detailSummary(_ detail: [String: String]) -> String {
        detail
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: " · ")
    }
}
