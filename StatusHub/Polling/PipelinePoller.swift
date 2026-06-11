import Foundation

@MainActor
class PipelinePoller {
    private let store: RepositoryStore
    private let service: GitLabServiceProtocol
    private let resolver: BranchResolver
    private var timer: Timer?
    private var isPolling = false

    init(store: RepositoryStore, service: GitLabServiceProtocol = GitLabService()) {
        self.store = store
        self.service = service
        self.resolver = BranchResolver(service: service)
    }

    func start() {
        stopTimer()
        let interval = TimeInterval(store.settings.pollInterval)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollOnce(token: KeychainService.loadToken() ?? "")
            }
        }
        // poll immediately on start
        Task { @MainActor in
            await pollOnce(token: KeychainService.loadToken() ?? "")
        }
    }

    func stop() {
        stopTimer()
    }

    func pollOnce(token: String, manual: Bool = false) async {
        if isPolling && !manual { return }
        isPolling = true
        defer { isPolling = false }

        let settings = store.settings
        await withTaskGroup(of: Void.self) { group in
            for repo in settings.repositories {
                for watch in repo.branches {
                    group.addTask { @MainActor in
                        await self.pollBranch(
                            repo: repo,
                            watch: watch,
                            gitlabUrl: settings.gitlabUrl,
                            token: token
                        )
                    }
                }
            }
        }
    }

    private func pollBranch(repo: Repository, watch: BranchWatch, gitlabUrl: String, token: String) async {
        let resolvedBranch: String?
        do {
            resolvedBranch = try await resolver.resolve(
                selector: watch.selector,
                gitlabUrl: gitlabUrl,
                projectPath: repo.projectPath,
                token: token
            )
        } catch let error as GitLabError {
            store.applyError(error, forBranch: watch.id)
            return
        } catch {
            store.applyError(.networkError(error), forBranch: watch.id)
            return
        }

        guard let branch = resolvedBranch else {
            store.applyError(.noBranchMatch, forBranch: watch.id)
            return
        }

        do {
            let result = try await service.fetchLatestPipeline(
                gitlabUrl: gitlabUrl,
                projectPath: repo.projectPath,
                branch: branch,
                token: token
            )
            // Only fetch a baseline (and pay the extra API call) when the pipeline
            // is still in flight — finished pipelines don't need a progress estimate.
            var baseline: TimeInterval? = nil
            if result.status == .running || result.status == .pending {
                if let durations = try? await service.fetchRecentSuccessDurations(
                    gitlabUrl: gitlabUrl,
                    projectPath: repo.projectPath,
                    branch: branch,
                    token: token,
                    limit: 5
                ), !durations.isEmpty {
                    baseline = durations.reduce(0, +) / TimeInterval(durations.count)
                }
            }
            store.applyResult(result, resolvedBranch: branch, baselineDuration: baseline, forBranch: watch.id)
        } catch let error as GitLabError {
            store.applyError(error, forBranch: watch.id, resolvedBranch: branch)
        } catch {
            store.applyError(.networkError(error), forBranch: watch.id, resolvedBranch: branch)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
