import Foundation

@MainActor
final class CodexAutomationStore: ObservableObject, StatusProvider {
    let providerId = "codex-automation"
    let providerTitle = "Codex 自动化"
    let providerIcon = "bolt.rectangle"

    @Published private(set) var runs: [CodexAutomationRun] = []
    @Published var errorMessage: String?

    private var timer: Timer?
    private let fileManager: FileManager
    private let runsDirectory: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL = CodexAutomationStore.defaultBaseDirectory()
    ) {
        self.fileManager = fileManager
        self.runsDirectory = baseDirectory.appendingPathComponent("runs", isDirectory: true)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    nonisolated static func defaultBaseDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("IntelliAutomation", isDirectory: true)
    }

    var overallStatus: HubStatus {
        runs.map { $0.status.hubStatus }.max() ?? .idle
    }

    var activeRuns: [CodexAutomationRun] {
        runs.filter { $0.status == .running || $0.status == .pending }
    }

    func start() {
        reload()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func refresh() async {
        reload()
    }

    func reload() {
        do {
            try fileManager.createDirectory(at: runsDirectory, withIntermediateDirectories: true)
            let files = try fileManager.contentsOfDirectory(
                at: runsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "json" }

            let loaded = files.compactMap(loadRun)
            runs = loaded.sorted(by: sortRuns)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveNote(_ note: String, for run: CodexAutomationRun) {
        let file = runsDirectory.appendingPathComponent("\(run.runId).json")
        var updated = run
        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let data = try encoder.encode(updated)
            try data.write(to: file, options: [.atomic])
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadRun(from url: URL) -> CodexAutomationRun? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CodexAutomationRun.self, from: data)
    }

    private func sortRuns(_ lhs: CodexAutomationRun, _ rhs: CodexAutomationRun) -> Bool {
        let left = lhs.startedAt ?? lhs.finishedAt ?? .distantPast
        let right = rhs.startedAt ?? rhs.finishedAt ?? .distantPast
        return left > right
    }
}
