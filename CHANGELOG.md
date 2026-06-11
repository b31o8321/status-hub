# Changelog

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
