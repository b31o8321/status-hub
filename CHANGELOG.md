# Changelog

## 0.1.16

- Add bundled provider support for general-purpose marketplace providers.
- Ship Mac System as a built-in provider resource instead of requiring a
  separate GitHub install for new users.
- Keep GitHub-installed providers as the mechanism for custom team providers.

## 0.1.15

- Replace document-specific link labels with generic provider links.
- Add direct open buttons and progress bars for provider detail items.

## 0.1.14

- Make plugin updates recover from dirty plugin worktrees.
- Preserve provider `runtime/` data while force-refreshing plugin code.

## 0.1.13

- Add provider-owned external configuration helpers for complex settings flows.
- Render `externalConfig` fields as action buttons instead of editable JSON.

## 0.1.12

- Add GitHub Actions DMG packaging with unsigned-app install instructions.
- Add provider implementation standard documentation.
- Support provider icons from plugin-relative image paths such as SVG files.

## 0.1.11

- Require provider manifests to declare an icon and render pinned provider
  navigation as compact icon-only tabs.

## 0.1.10

- Cap provider output links in the compact overview menu and job cards.

## 0.1.9

- Move provider item actions into compact icon buttons beside the item status.

## 0.1.8

- Replace long inline log paths in job cards with an "打开日志目录" Finder shortcut.

## 0.1.7

- Preserve provider `runtime/` data, including local configuration, while installing or updating GitHub plugins.

## 0.1.4

- Add a settings overview with provider install counts, update status, update-all, and Finder shortcuts.
- Move provider-owned configuration into collapsible installed-provider sections.
- Restore first-level pinned provider pages in the menu popover while keeping the overview compact.
- Use macOS material backgrounds for the menu popover.

## 0.1.3

- Add provider item actions so providers can expose manual trigger and toggle buttons.
- Add provider item links for recent generated documents and other quick links.
- Render only user-facing provider details in the main popover.

## 0.1.2

- Move plugin management out of the main popover and into Settings.
- Keep the main popover focused on 总览 plus pinned provider pages.
- Add per-provider 一级展示 pinning from the installed-provider list and overview rows.
- Reorder plugin management by usage frequency: 已安装, 市场, GitHub.

## 0.1.1

- Install and update tagged plugins by checking out the latest Git tag.
- Show marketplace updates only when a newer remote tag exists.
- Collapse provider metric details by default so multiple providers remain visible.
- Clean up stale managed provider processes before launching a provider command.

## 0.1.0

Initial Status Hub release.

- Reset app version to `0.1.0` / build `1`.
- Keep the app empty after installation.
- Add the first marketplace page with the general-purpose Mac System provider.
- Support local provider registration through JSON manifests.
- Support provider plugin installation from GitHub repositories.
- Add timeout handling and partial-clone cleanup for plugin installation.
- Start provider commands declared by plugin manifests.
- Read provider status snapshots from JSON files.
- Render optional provider item values and details.
- Show hub overview and installed provider summaries from the menu bar.
- Remove previous single-purpose monitor code from the app runtime.
