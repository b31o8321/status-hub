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

## Install

Download `StatusHub-<version>.dmg` from GitHub Actions artifacts or a tagged
release, open it, and drag `StatusHub.app` to `Applications`.

Status Hub is currently unsigned and not notarized. After copying the app, run:

```bash
xattr -dr com.apple.quarantine /Applications/StatusHub.app
```

If macOS reports a permission error:

```bash
sudo xattr -dr com.apple.quarantine /Applications/StatusHub.app
```

The DMG also includes `安装说明.md` with the same Gatekeeper unlock steps.

## Provider Standard

Provider implementation rules are documented in
[docs/provider-standard.md](docs/provider-standard.md).

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

Current app version: `0.1.12` / build `13`.

`0.1.2` keeps the app as the menu-bar shell, provider installer, provider
process manager, and status renderer. Provider management lives in Settings so
the main popover stays focused on live status.
`0.1.3` adds provider-declared actions and links, allowing a provider to expose
manual trigger buttons, schedule toggles, and recent generated documents without
custom Hub code.
`0.1.4` refines the hub UI with a compact translucent overview, first-level
pages for pinned providers, collapsible provider settings, and a settings
overview for install status, updates, and local directories.
`0.1.7` preserves provider `runtime/` data such as local configuration while
installing or updating GitHub plugins.
`0.1.8` keeps long log paths out of job summaries and exposes them as a Finder
shortcut instead.
`0.1.9` moves provider item actions into compact icon buttons beside each
item's status.
`0.1.10` caps provider output links in compact menus and job cards so recent
documents cannot stretch the status surface.
`0.1.11` requires each provider to declare an icon and uses icon-only pinned
provider navigation.
`0.1.12` adds unsigned DMG packaging docs, provider standard docs, and
plugin-relative image icons for providers.

## UI

The menu bar popover opens on **总览** by default:

- 总览: overall hub status and compact provider summaries.
- Fixed providers: providers marked as fixed in Settings or the overview appear
  beside 总览 as first-level pages with detailed status and actions.

The settings window is also hub-oriented:

- 总览: installed provider count, install status, update status, and local
  provider directories with Finder shortcuts.
- 已安装: provider-owned configuration forms.
- 市场: searchable marketplace.
- GitHub: plugin installation from repository URLs.

## Marketplace

The built-in marketplace only lists general-purpose plugins. Custom plugins such
as team-specific GitLab monitors or Intelli automation providers should be
installed through the GitHub tab instead of being fixed marketplace entries.

Current marketplace plugins:

- Mac System: CPU, memory, network, battery, disk, and temperature status.

## GitHub Plugin Installation

Open Status Hub Settings, switch to **插件 > GitHub**, paste a GitHub URL, and
click install. The app clones or pulls the repository under:

```text
~/Library/Application Support/StatusHub/plugins/
```

Each plugin repository must provide this file at its root. See
[docs/provider-standard.md](docs/provider-standard.md) for the complete schema.

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

`providers[].icon` is required. It may be a valid SF Symbol name or a
plugin-relative image path such as `assets/gitlab-icon.svg`.

If `command` is present, Status Hub starts that command and passes:

- `STATUS_HUB_PROVIDER_ID`
- `STATUS_HUB_STATUS_FILE`
- `STATUS_HUB_CONFIG_FILE`
- `STATUS_HUB_DATA_DIR`

The provider command should keep running and write the status file atomically.
Status Hub does not load plugin code into the app process; plugins communicate by
status files.

External provider registration and status file details are covered in
[docs/provider-standard.md](docs/provider-standard.md).

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
