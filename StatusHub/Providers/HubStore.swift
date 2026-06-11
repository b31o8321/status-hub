import Foundation
import Combine

@MainActor
final class HubStore: ObservableObject {
    @Published var externalProviderStore: ExternalProviderStore

    private var cancellables = Set<AnyCancellable>()

    init(externalProviderStore: ExternalProviderStore) {
        self.externalProviderStore = externalProviderStore

        externalProviderStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    var overallStatus: HubStatus {
        externalProviderStore.overallStatus
    }

    var statusLabel: String {
        providerCount == 0 ? "未配置" : overallStatus.label
    }

    var activeCount: Int {
        externalProviderStore.activeCount
    }

    var attentionCount: Int {
        externalProviderStore.attentionCount
    }

    var providerCount: Int {
        externalProviderStore.providers.count
    }

    var pluginCount: Int {
        externalProviderStore.installedPlugins.count
    }
}
