# Status Hub

macOS menu bar hub for local and GitHub-installed status providers.

Status Hub starts empty after installation. It does not ship with domain-specific
providers enabled by default. Every status source is installed or registered as
a provider plugin.

The app is responsible for:

- Installing or updating provider plugins from GitHub repositories.
- Starting provider commands declared by plugin manifests.
- Reading provider status JSON files.
- Showing current jobs, history summaries, artifacts, notes, and quick links.

## Architecture

```text
StatusHub
  AppDelegate
    HubStore
      ExternalProviderStore
        ~/Library/Application Support/StatusHub/providers/*.json
        ~/Library/Application Support/StatusHub/plugins/*/statushub-plugin.json
```

## Version

Current app version: `0.1.2` / build `3`.

`0.1.2` keeps the app as the menu-bar shell, provider installer, provider
process manager, and status renderer. Provider management lives in Settings so
the main popover stays focused on live status.

## UI

The menu bar popover opens on **总览** by default:

- 总览: overall hub status and provider summaries.
- Pinned providers: providers marked as **一级展示** in Settings appear beside
  总览 as first-level pages.

The settings window is also hub-oriented:

- 总览: current hub status and local data directories.
- 插件: installed providers, marketplace, and GitHub plugin installation.

## Marketplace

The built-in marketplace only lists general-purpose plugins. Custom plugins such
as team-specific GitLab monitors or Intelli automation providers should be
installed through the GitHub tab instead of being fixed marketplace entries.

Current marketplace plugins:

- Mac System: CPU, memory, network, battery, disk, and temperature status.

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

The app process only hosts the hub. Provider implementations should use the JSON
registration or GitHub plugin protocol below.

## GitHub Plugin Installation

Open Status Hub Settings, switch to **插件 > GitHub**, paste a GitHub URL, and
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
  "id": "example-status-provider",
  "title": "Example Status Provider",
  "version": "0.1.0",
  "providers": [
    {
      "id": "main",
      "title": "Example Provider",
      "icon": "square.stack.3d.up",
      "statusFile": "runtime/status.json",
      "command": "bin/example-provider",
      "arguments": [],
      "workingDirectory": "."
    }
  ]
}
```

If `command` is present, Status Hub starts that command and passes:

- `STATUS_HUB_PROVIDER_ID`
- `STATUS_HUB_STATUS_FILE`
- `STATUS_HUB_CONFIG_FILE` and `STATUS_HUB_DATA_DIR` are planned for configurable
  providers.

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
  "id": "local-example",
  "title": "Local Example",
  "icon": "square.stack.3d.up",
  "statusFile": "~/Library/Application Support/LocalExample/status.json"
}
```

The external program then keeps `statusFile` up to date.

Status file example:

```json
{
  "status": "attention",
  "summary": "2 个任务需要确认，1 个正在运行",
  "updatedAt": "2026-06-11T12:30:00+08:00",
  "items": [
    {
      "id": "daily-job",
      "title": "每日任务",
      "subtitle": "等待人工确认",
      "status": "attention",
      "url": "https://example.com/artifacts/daily-job",
      "value": "2",
      "detail": {
        "owner": "team"
      }
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
