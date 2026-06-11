import Foundation
import Combine

@MainActor
final class GitLabProvider: ObservableObject, StatusProvider {
    let providerId = "gitlab"
    let providerTitle = "GitLab Pipeline"
    let providerIcon = "point.3.connected.trianglepath.dotted"

    @Published var store: RepositoryStore

    private let poller: PipelinePoller
    private var cancellables = Set<AnyCancellable>()

    init() {
        let repositoryStore = RepositoryStore()
        self.store = repositoryStore
        self.poller = PipelinePoller(store: repositoryStore)

        repositoryStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        repositoryStore.$settings.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.poller.stop()
                self?.poller.start()
            }
        }.store(in: &cancellables)
    }

    var overallStatus: HubStatus {
        store.hubStatus
    }

    func start() {
        poller.start()
    }

    func refresh() async {
        await poller.pollOnce(token: KeychainService.loadToken() ?? "", manual: true)
    }
}
