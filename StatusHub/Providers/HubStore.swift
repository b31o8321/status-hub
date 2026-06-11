import Foundation
import Combine

@MainActor
final class HubStore: ObservableObject {
    @Published var gitLabProvider: GitLabProvider
    @Published var automationStore: CodexAutomationStore
    @Published var externalProviderStore: ExternalProviderStore

    private var cancellables = Set<AnyCancellable>()

    init(
        gitLabProvider: GitLabProvider,
        automationStore: CodexAutomationStore,
        externalProviderStore: ExternalProviderStore
    ) {
        self.gitLabProvider = gitLabProvider
        self.automationStore = automationStore
        self.externalProviderStore = externalProviderStore

        gitLabProvider.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        automationStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        externalProviderStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    var overallStatus: HubStatus {
        [
            gitLabProvider.overallStatus,
            automationStore.overallStatus,
            externalProviderStore.overallStatus
        ].max() ?? .unknown
    }

    var activeCount: Int {
        gitLabProvider.store.states.filter { $0.status == .running || $0.status == .pending }.count
            + automationStore.activeRuns.count
            + externalProviderStore.activeCount
    }

    var attentionCount: Int {
        automationStore.runs.filter { $0.status == .needsConfirmation }.count
            + externalProviderStore.attentionCount
    }
}
