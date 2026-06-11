import SwiftUI

struct ProjectSearchView: View {
    let gitlabUrl: String
    let token: String
    let service: GitLabServiceProtocol
    @Binding var selectedRepos: [Repository]

    @State private var searchText: String = ""
    @State private var searchResults: [GitLabProject] = []
    @State private var loadingState: LoadState = .idle
    @State private var errorMessage: String = ""
    @State private var searchTask: Task<Void, Never>?

    enum LoadState {
        case idle, loading, loaded, failed
    }

    private var normalizedUrl: String {
        gitlabUrl.hasSuffix("/") ? String(gitlabUrl.dropLast()) : gitlabUrl
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索仓库名称...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Already-selected repos always shown at top
                    if !selectedRepos.isEmpty {
                        sectionHeader("已选择")
                        ForEach(selectedRepos) { repo in
                            selectedRepoCard(repo: repo)
                            Divider().padding(.leading, 40)
                        }
                    }

                    // Search results (excluding already-selected by projectPath)
                    let unselected = searchResults.filter { p in
                        !selectedRepos.contains { $0.projectPath == p.pathWithNamespace }
                    }
                    if !searchResults.isEmpty || loadingState == .loading {
                        sectionHeader("搜索结果")
                    }
                    switch loadingState {
                    case .loading:
                        HStack {
                            ProgressView().scaleEffect(0.7)
                            Text("加载中...").font(.caption).foregroundColor(.secondary)
                        }
                        .padding()
                    case .failed:
                        VStack(alignment: .leading, spacing: 4) {
                            Text("加载失败")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            Button("重试") { loadProjects() }
                                .font(.caption)
                        }
                        .padding()
                    case .loaded where searchResults.isEmpty:
                        Text("未找到相关仓库")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    case .loaded:
                        ForEach(unselected) { project in
                            unselectedRepoRow(project: project)
                            Divider().padding(.leading, 40)
                        }
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .onAppear { loadProjects() }
        .onChange(of: searchText) { _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                loadProjects()
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    // MARK: - Unselected (single line, no expanded controls)

    @ViewBuilder
    private func unselectedRepoRow(project: GitLabProject) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "square")
                .foregroundColor(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name).fontWeight(.medium)
                Text(project.pathWithNamespace).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            addProject(pathWithNamespace: project.pathWithNamespace, name: project.name, defaultBranch: project.defaultBranch)
        }
    }

    // MARK: - Selected (with N branch editors)

    @ViewBuilder
    private func selectedRepoCard(repo: Repository) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.square.fill")
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(repo.name).fontWeight(.medium)
                    Text(repo.projectPath).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    selectedRepos.removeAll { $0.id == repo.id }
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("移除该项目")
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(repo.branches) { watch in
                    HStack(alignment: .top, spacing: 6) {
                        BranchSelectorEditor(
                            initialSelector: watch.selector,
                            onSelectorChange: { newSelector in
                                updateSelector(repoId: repo.id, branchId: watch.id, newSelector: newSelector)
                            },
                            searchBranches: { term in
                                do {
                                    let branches = try await service.fetchBranches(
                                        gitlabUrl: normalizedUrl,
                                        token: token,
                                        projectPath: repo.projectPath,
                                        search: term.isEmpty ? nil : term
                                    )
                                    return branches.map(\.name)
                                } catch {
                                    return []
                                }
                            }
                        )
                        if repo.branches.count > 1 {
                            Button {
                                removeBranch(repoId: repo.id, branchId: watch.id)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("移除该分支")
                        }
                    }
                }
                Button {
                    addBranch(repoId: repo.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                        Text("添加分支").font(.caption)
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 30)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Selection / branch mutation

    private func addProject(pathWithNamespace: String, name: String, defaultBranch: String?) {
        // If already present, do nothing (user can use "+ 添加分支" inside the card).
        if selectedRepos.contains(where: { $0.projectPath == pathWithNamespace }) { return }
        let initialBranch = defaultBranch ?? "main"
        selectedRepos.append(Repository(
            name: name,
            projectPath: pathWithNamespace,
            branchSelector: .fixed(initialBranch)
        ))
    }

    private func addBranch(repoId: UUID) {
        guard let idx = selectedRepos.firstIndex(where: { $0.id == repoId }) else { return }
        // New watches default to fixed "main" — user picks the branch via the editor.
        selectedRepos[idx].branches.append(BranchWatch(selector: .fixed("main")))
    }

    private func removeBranch(repoId: UUID, branchId: UUID) {
        guard let idx = selectedRepos.firstIndex(where: { $0.id == repoId }) else { return }
        selectedRepos[idx].branches.removeAll { $0.id == branchId }
        // If the user removed the last branch, treat that as removing the project.
        if selectedRepos[idx].branches.isEmpty {
            selectedRepos.remove(at: idx)
        }
    }

    private func updateSelector(repoId: UUID, branchId: UUID, newSelector: BranchSelector) {
        guard let repoIdx = selectedRepos.firstIndex(where: { $0.id == repoId }) else { return }
        guard let branchIdx = selectedRepos[repoIdx].branches.firstIndex(where: { $0.id == branchId }) else { return }
        selectedRepos[repoIdx].branches[branchIdx].selector = newSelector
    }

    // MARK: - Loaders

    private func loadProjects() {
        loadingState = .loading
        errorMessage = ""
        Task {
            do {
                let projects = try await service.fetchProjects(
                    gitlabUrl: normalizedUrl,
                    token: token,
                    search: searchText
                )
                await MainActor.run {
                    searchResults = projects
                    loadingState = .loaded
                }
            } catch let e as GitLabError {
                await MainActor.run {
                    errorMessage = e.errorDescription ?? "\(e)"
                    loadingState = .failed
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    loadingState = .failed
                }
            }
        }
    }

}

// MARK: - BranchSelectorEditor

private struct BranchSelectorEditor: View {
    let initialSelector: BranchSelector
    let onSelectorChange: (BranchSelector) -> Void
    let searchBranches: (String) async -> [String]

    enum Mode: String, CaseIterable, Identifiable {
        case fixed = "固定分支"
        case rule = "动态匹配最新"
        case regex = "自定义正则"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .fixed
    @State private var fixedBranch: String = "main"
    @State private var rulePrefix: String = "test"
    @State private var ruleFormat: BranchDateFormat = .yyyymmdd
    @State private var regexPattern: String = "^test-\\d{8}$"
    @State private var initialized: Bool = false
    @State private var lastPublished: BranchSelector? = nil

    @State private var suggestions: [String] = []
    @State private var suggestionsLoading: Bool = false
    @State private var showSuggestions: Bool = false
    @State private var suggestQuery: String = ""
    @State private var suggestTask: Task<Void, Never>? = nil
    @FocusState private var fixedFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("分支", selection: $mode) {
                ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .fixed:
                fixedSection
            case .rule:
                ruleSection
            case .regex:
                regexSection
            }
        }
        .font(.caption)
        .onAppear { initializeFromSelector() }
        .onChange(of: mode) { _ in publishSelector() }
        .onChange(of: fixedBranch) { _ in publishSelector() }
        .onChange(of: rulePrefix) { _ in publishSelector() }
        .onChange(of: ruleFormat) { _ in publishSelector() }
        .onChange(of: regexPattern) { _ in publishSelector() }
    }

    @ViewBuilder
    private var fixedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("分支名（输入可搜索）", text: $fixedBranch)
                    .textFieldStyle(.roundedBorder)
                    .focused($fixedFieldFocused)
                    .onChange(of: fixedBranch) { newValue in
                        scheduleBranchSearch(newValue)
                    }
                    .onChange(of: fixedFieldFocused) { focused in
                        if focused {
                            showSuggestions = true
                            if suggestions.isEmpty && !suggestionsLoading {
                                scheduleBranchSearch(fixedBranch)
                            }
                        } else {
                            hideSuggestionsAfterDelay()
                        }
                    }
                Button {
                    showSuggestions.toggle()
                    if showSuggestions && suggestions.isEmpty && !suggestionsLoading {
                        scheduleBranchSearch(fixedBranch)
                    }
                } label: {
                    Image(systemName: showSuggestions ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if showSuggestions {
                suggestionList
            }
        }
    }

    @ViewBuilder
    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if suggestionsLoading && suggestions.isEmpty {
                HStack {
                    ProgressView().scaleEffect(0.5)
                    Text("加载分支...").foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            } else if suggestions.isEmpty {
                Text(suggestQuery.isEmpty ? "（无分支）" : "未找到匹配分支")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions, id: \.self) { branch in
                            Button {
                                fixedBranch = branch
                                showSuggestions = false
                                fixedFieldFocused = false
                            } label: {
                                HStack {
                                    Text(branch)
                                        .foregroundColor(branch == fixedBranch ? .accentColor : .primary)
                                    Spacer()
                                    if branch == fixedBranch {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.3))
        )
    }

    private func scheduleBranchSearch(_ term: String) {
        suggestTask?.cancel()
        suggestQuery = term
        let captured = term
        suggestTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            await MainActor.run { suggestionsLoading = true }
            let results = await searchBranches(captured)
            if Task.isCancelled { return }
            await MainActor.run {
                suggestions = results
                suggestionsLoading = false
            }
        }
    }

    private func hideSuggestionsAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            await MainActor.run {
                if !fixedFieldFocused {
                    showSuggestions = false
                }
            }
        }
    }

    @ViewBuilder
    private var ruleSection: some View {
        HStack {
            Text("前缀:").foregroundColor(.secondary)
            TextField("test", text: $rulePrefix)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            Picker("", selection: $ruleFormat) {
                ForEach(BranchDateFormat.allCases, id: \.self) { fmt in
                    Text(fmt.displayName).tag(fmt)
                }
            }
            .labelsHidden()
            .frame(width: 130)
        }
        Text("匹配 \(BranchDateFormat.example(prefix: rulePrefix, format: ruleFormat))")
            .foregroundColor(.secondary)
            .font(.caption2)
    }

    @ViewBuilder
    private var regexSection: some View {
        TextField("^test-\\d{8}$", text: $regexPattern)
            .textFieldStyle(.roundedBorder)
            .font(.system(.caption, design: .monospaced))
    }

    private func initializeFromSelector() {
        guard !initialized else { return }
        initialized = true
        lastPublished = initialSelector
        switch initialSelector {
        case .fixed(let name):
            mode = .fixed
            fixedBranch = name
        case .rule(let prefix, let format):
            mode = .rule
            rulePrefix = prefix
            ruleFormat = format
        case .regex(let pattern):
            mode = .regex
            regexPattern = pattern
        }
    }

    private func publishSelector() {
        guard initialized else { return }
        let selector: BranchSelector
        switch mode {
        case .fixed: selector = .fixed(fixedBranch)
        case .rule: selector = .rule(prefix: rulePrefix, format: ruleFormat)
        case .regex: selector = .regex(regexPattern)
        }
        if selector != lastPublished {
            lastPublished = selector
            onSelectorChange(selector)
        }
    }
}

private extension BranchDateFormat {
    static func example(prefix: String, format: BranchDateFormat) -> String {
        let p = prefix.isEmpty ? "test" : prefix
        switch format {
        case .yyyymmdd: return "\(p)-20260326"
        case .yyyymmddDashed: return "\(p)-2026-03-26"
        case .yyyymmddDotted: return "\(p)-2026.03.26"
        case .yyyymmddWithTail: return "\(p)-20260326-hotfix"
        }
    }
}
