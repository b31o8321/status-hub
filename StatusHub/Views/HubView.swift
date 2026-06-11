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
            if !pinnedProviders.isEmpty {
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
            }

            if selectedPage == HubPage.overview {
                OverviewView(store: store)
            } else if let provider = pinnedProviders.first(where: { $0.id == selectedPage }) {
                ProviderDetailView(provider: provider, externalStore: store.externalProviderStore)
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

    private var externalStore: ExternalProviderStore {
        store.externalProviderStore
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if store.providerCount == 0 {
                    EmptyHubView()
                } else {
                    OverviewHeaderCard(store: store)

                    ForEach(externalStore.providers) { provider in
                        ProviderCompactRow(provider: provider, externalStore: externalStore)
                    }
                }
            }
            .padding(12)
        }
    }
}

private struct OverviewHeaderCard: View {
    @ObservedObject var store: HubStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .frame(width: 18)
                    .foregroundColor(store.overallStatus.color)
                Text("总览")
                    .fontWeight(.semibold)
                Spacer()
                Text(store.overallStatus.label)
                    .font(.caption)
                    .foregroundColor(store.overallStatus.color)
            }

            Text(summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
    }

    private var summary: String {
        var parts = ["\(store.pluginCount) 个插件", "\(store.providerCount) 个 Provider"]
        if store.activeCount > 0 {
            parts.append("\(store.activeCount) 个运行中")
        }
        if store.attentionCount > 0 {
            parts.append("\(store.attentionCount) 个待确认")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ProviderCompactRow: View {
    let provider: ExternalProviderRuntime
    @ObservedObject var externalStore: ExternalProviderStore

    private var actions: [(item: ExternalProviderItem, action: ExternalProviderAction)] {
        (provider.snapshot?.items ?? []).flatMap { item in
            (item.actions ?? []).map { (item, $0) }
        }
    }

    private var links: [ExternalProviderLink] {
        (provider.snapshot?.items ?? []).flatMap { $0.links ?? [] }
    }

    private var isPinned: Bool {
        externalStore.isProviderPinned(provider.id)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: provider.icon)
                .frame(width: 18)
                .foregroundColor(provider.status.color)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(provider.title)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if provider.status == .running {
                        ProgressView()
                            .scaleEffect(0.45)
                            .frame(width: 12, height: 12)
                    }
                }

                Text(provider.snapshot?.summary ?? provider.errorMessage ?? "无状态摘要")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button {
                    externalStore.setProviderPinned(provider.id, pinned: !isPinned)
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .foregroundColor(isPinned ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "取消固定" : "固定到顶部导航")

                if !links.isEmpty {
                    Menu {
                        ForEach(links.prefix(8)) { link in
                            Button(link.title) {
                                open(link.url)
                            }
                        }
                    } label: {
                        Image(systemName: "doc.text")
                    }
                    .menuStyle(.borderlessButton)
                    .help("最近产出")
                }

                if !actions.isEmpty {
                    Menu {
                        ForEach(Array(actions.enumerated()), id: \.offset) { _, pair in
                            Button("\(pair.item.title) · \(pair.action.title)") {
                                externalStore.runAction(pair.action, for: pair.item, provider: provider)
                            }
                            .disabled(externalStore.isActionRunning(provider: provider, item: pair.item, action: pair.action))
                        }
                    } label: {
                        Image(systemName: "bolt")
                    }
                    .menuStyle(.borderlessButton)
                    .help("快捷操作")
                }

                Text(provider.status.label)
                    .font(.caption)
                    .foregroundColor(provider.status.color)
                    .frame(minWidth: 42, alignment: .trailing)
            }
            .padding(.top, 1)
        }
        .padding(.vertical, 8)
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString), url.scheme != nil {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: urlString))
        }
    }
}

private struct ProviderDetailView: View {
    let provider: ExternalProviderRuntime
    @ObservedObject var externalStore: ExternalProviderStore

    var body: some View {
        ScrollView {
            ProviderDetailSection(provider: provider, externalStore: externalStore)
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

private struct ProviderDetailSection: View {
    let provider: ExternalProviderRuntime
    @ObservedObject var externalStore: ExternalProviderStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderSummaryRow(
                title: provider.title,
                subtitle: provider.snapshot?.summary ?? provider.errorMessage ?? "无状态摘要",
                status: provider.status,
                icon: provider.icon,
                isPinned: true,
                togglePinned: {
                    externalStore.setProviderPinned(provider.id, pinned: false)
                }
            )

            if let error = provider.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            ForEach(provider.snapshot?.items ?? []) { item in
                ProviderItemCard(item: item, provider: provider, externalStore: externalStore)
            }
        }
        .padding(10)
    }
}

private struct ProviderItemCard: View {
    let item: ExternalProviderItem
    let provider: ExternalProviderRuntime
    @ObservedObject var externalStore: ExternalProviderStore

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
            if let actions = item.actions, !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(actions) { action in
                        Button {
                            externalStore.runAction(action, for: item, provider: provider)
                        } label: {
                            if externalStore.isActionRunning(provider: provider, item: item, action: action) {
                                ProgressView().scaleEffect(0.55)
                            } else {
                                Label(action.title, systemImage: action.destructive == true ? "exclamationmark.triangle" : "play.fill")
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                        .disabled(externalStore.isActionRunning(provider: provider, item: item, action: action))
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.top, 2)
            }
            if let links = item.links, !links.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(links.prefix(3)) { link in
                        Link(destination: URL(string: link.url) ?? URL(fileURLWithPath: link.url)) {
                            Label(link.title, systemImage: "doc.text")
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 2)
            }
            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            if let detail = item.detail, !displayDetails(detail).isEmpty {
                Text(detailSummary(detail))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    private func detailSummary(_ detail: [String: String]) -> String {
        displayDetails(detail)
            .map { "\($0.title): \($0.value)" }
            .joined(separator: " · ")
    }

    private func displayDetails(_ detail: [String: String]) -> [(title: String, value: String)] {
        let orderedKeys = ["nextRunText", "lastRunText", "finishedText", "logPath"]
        let labels = [
            "nextRunText": "下次执行",
            "lastRunText": "最近运行",
            "finishedText": "完成时间",
            "logPath": "日志"
        ]
        return orderedKeys.compactMap { key in
            guard let value = detail[key], !value.isEmpty else { return nil }
            return (labels[key] ?? key, value)
        }
    }
}
