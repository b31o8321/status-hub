import SwiftUI
import AppKit

struct ExternalProvidersView: View {
    @ObservedObject var store: ExternalProviderStore
    @State private var pluginURL = ""

    var body: some View {
        VStack(spacing: 0) {
            installBar
            Divider()

            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                Divider()
            }

            if store.providers.isEmpty {
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

    private var installBar: some View {
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
    }
}

private struct ExternalProviderRow: View {
    let provider: ExternalProviderRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: provider.icon)
                    .frame(width: 16)
                    .foregroundColor(provider.status.color)
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
                        .lineLimit(2)
                }

                if let updatedAt = provider.snapshot?.updatedAt {
                    Text(relativeFormatter.localizedString(for: updatedAt, relativeTo: Date()))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                ForEach((provider.snapshot?.items ?? []).prefix(5)) { item in
                    ExternalProviderItemRow(item: item)
                }
            }

            if provider.command != nil {
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
