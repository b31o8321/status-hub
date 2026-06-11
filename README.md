# Status Hub

macOS menu bar hub for local status providers.

Status Hub starts as a fork of the existing GitLab Monitor menu bar app, then
turns each status source into a provider. The first built-in providers are:

- GitLab Pipeline: monitors configured GitLab projects and branches.
- Codex Automation: reads local automation run records produced by scheduled
  Codex jobs.
- External Providers: lets other local programs register status providers by
  writing JSON manifests.
- GitHub Plugins: installs provider plugins from GitHub repositories.

## Architecture

```text
StatusHub
  AppDelegate
    HubStore
      GitLabProvider
        RepositoryStore
        PipelinePoller
      CodexAutomationStore
        ~/Library/Application Support/IntelliAutomation/runs/*.json
      ExternalProviderStore
        ~/Library/Application Support/StatusHub/providers/*.json
        ~/Library/Application Support/StatusHub/plugins/*/statushub-plugin.json
```

## UI

The menu bar popover opens on the **总览** tab by default. Provider-specific
views live behind their own tabs:

- 总览: overall hub status and provider summaries.
- 自动化: Codex automation runs and artifacts.
- GitLab: GitLab pipeline rows.
- 外部: external providers and plugin installation.

The settings window is also hub-oriented:

- 总览: current hub status and local data directories.
- GitLab: GitLab connection and repository selection.
- 插件: install or inspect GitHub provider plugins.

Provider contract:

```swift
@MainActor
protocol StatusProvider: ObservableObject {
    var providerId: String { get }
    var providerTitle: String { get }
    var providerIcon: String { get }
    var overallStatus: HubStatus { get }

    func start()
    func refresh() async
}
```

Built-in providers can implement this Swift protocol directly. External programs
should use the JSON registration protocol below.

## GitHub Plugin Installation

Open the Status Hub popover, switch to the **外部** tab, paste a GitHub URL, and
click install. The app clones or pulls the repository under:

```text
~/Library/Application Support/StatusHub/plugins/
```

Each plugin repository must provide this file at its root:

```text
statushub-plugin.json
```

Plugin manifest example:

```json
{
  "id": "gitlab-monitor",
  "title": "GitLab Monitor",
  "version": "0.1.0",
  "providers": [
    {
      "id": "pipeline",
      "title": "GitLab Pipeline",
      "icon": "point.3.connected.trianglepath.dotted",
      "statusFile": "runtime/status.json",
      "command": "bin/gitlab-provider",
      "arguments": [],
      "workingDirectory": "."
    }
  ]
}
```

If `command` is present, Status Hub starts that command and passes:

- `STATUS_HUB_PROVIDER_ID`
- `STATUS_HUB_STATUS_FILE`

The provider command should keep running and write the status file atomically.
Status Hub does not load plugin code into the app process; plugins communicate by
status files.

## External Provider Registration

External programs register themselves by writing a manifest file to:

```text
~/Library/Application Support/StatusHub/providers/<provider-id>.json
```

Manifest example:

```json
{
  "id": "gitlab-monitor-legacy",
  "title": "Legacy GitLab Monitor",
  "icon": "point.3.connected.trianglepath.dotted",
  "statusFile": "~/Library/Application Support/GitLabMonitor/status.json"
}
```

The external program then keeps `statusFile` up to date.

Status file example:

```json
{
  "status": "attention",
  "summary": "2 个 pipeline 失败，1 个正在运行",
  "updatedAt": "2026-06-11T12:30:00+08:00",
  "items": [
    {
      "id": "shulex-intelli-master",
      "title": "shulex-intelli / master",
      "subtitle": "pipeline failed",
      "status": "failed",
      "url": "https://gitlab.example.com/group/project/-/pipelines/123"
    }
  ]
}
```

Supported provider statuses:

- `idle`
- `success`
- `running`
- `attention`
- `failed`
- `unknown`

Recommended rule: external providers should write status files atomically, for
example write to a temp file and rename it to the target path.

## Codex Automation Run Format

Status Hub watches:

```text
~/Library/Application Support/IntelliAutomation/runs/*.json
```

Example:

```json
{
  "runId": "20260611-093000-daily-feedback-defect-triage",
  "jobType": "daily-feedback-defect-triage",
  "status": "needs_confirmation",
  "trigger": "scheduled",
  "startedAt": "2026-06-11T09:30:00+08:00",
  "finishedAt": "2026-06-11T09:36:42+08:00",
  "sprint": "Sprint 202606 15 - 19",
  "summary": "分析缺陷反馈 18 条，生成 5 个模块处理项",
  "artifacts": [
    {
      "title": "每日缺陷反馈分析",
      "url": "https://alidocs.dingtalk.com/i/nodes/..."
    }
  ],
  "logPath": "/Users/norman/Library/Application Support/IntelliAutomation/logs/20260611-093000-daily-feedback-defect-triage.log",
  "note": "人工确认前不写回 AI 表格。"
}
```

Supported automation statuses:

- `pending`
- `running`
- `success`
- `failed`
- `needs_confirmation`
- `canceled`
- `unknown`

## Build

Generate the Xcode project:

```bash
xcodegen generate
```

Build:

```bash
xcodebuild -project StatusHub.xcodeproj -scheme StatusHub -destination 'platform=macOS' build
```

Run tests:

```bash
xcodebuild test -project StatusHub.xcodeproj -scheme StatusHub -destination 'platform=macOS'
```
