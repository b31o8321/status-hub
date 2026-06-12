# Status Hub

[English](README.en.md)

Status Hub 是一个 macOS 菜单栏状态中心，用来承载内置、本地和 GitHub 安装的状态 Provider。

Status Hub 安装后默认不启用任何业务定制 Provider。每个状态来源都通过 Provider 插件安装或注册。

应用负责：

- 启用随 App 打包的通用 Provider。
- 从 GitHub 仓库安装或更新 Provider 插件。
- 启动插件 manifest 声明的 Provider 命令。
- 读取 Provider 写出的状态 JSON。
- 展示当前任务、历史摘要、产出物、备注和快捷链接。

## 安装

从 GitHub Actions artifacts 或 tagged release 下载 `StatusHub-<version>.dmg`，打开后将 `StatusHub.app` 拖到 `Applications`。

Status Hub 当前未签名、未公证。复制 App 后执行：

```bash
xattr -dr com.apple.quarantine /Applications/StatusHub.app
```

如果 macOS 提示权限不足：

```bash
sudo xattr -dr com.apple.quarantine /Applications/StatusHub.app
```

DMG 中也包含 `安装说明.md`，里面有相同的 Gatekeeper 放行步骤。

## Provider 标准

Provider 实现规范见 [docs/provider-standard.md](docs/provider-standard.md)。

## 架构

```text
StatusHub
  AppDelegate
    HubStore
      ExternalProviderStore
        ~/Library/Application Support/StatusHub/providers/*.json
        ~/Library/Application Support/StatusHub/plugins/*/statushub-plugin.json
```

## 版本

当前 App 版本：`0.1.17` / build `18`。

`0.1.2` 保持 App 作为菜单栏外壳、Provider 安装器、Provider 进程管理器和状态渲染器；Provider 管理放到设置页，让主弹窗聚焦实时状态。
`0.1.3` 增加 Provider 声明的 actions 和 links，允许 Provider 暴露手动触发、定时开关和近期生成文档，不需要 Hub 写定制代码。
`0.1.4` 优化 Hub UI：紧凑半透明总览、固定 Provider 一级页面、可折叠 Provider 设置，以及包含安装状态、更新状态、本地目录的设置总览。
`0.1.7` 安装或更新 GitHub 插件时保留 Provider `runtime/` 数据，例如本地配置。
`0.1.8` 不再在任务摘要里展示很长的日志路径，改为 Finder 快捷入口。
`0.1.9` 将 Provider item actions 放到每个 item 状态旁边的紧凑图标按钮里。
`0.1.10` 限制紧凑菜单和任务卡片里的 Provider 输出链接数量，避免近期文档把状态面板撑长。
`0.1.11` 要求每个 Provider 声明 icon，并使用纯图标的固定 Provider 导航。
`0.1.12` 增加未签名 DMG 打包说明、Provider 标准文档，以及插件相对路径图片 icon 支持。
`0.1.13` 增加 Provider 自有外部配置 helper，让 GitLab 项目/分支选择这类复杂设置可以用 Provider UI 完成，而不是编辑 JSON。
`0.1.14` 让 GitHub 插件更新能从脏工作区恢复，同时保留 Provider `runtime/` 数据。
`0.1.15` 改进 Provider 详情渲染，支持通用链接、直接打开按钮和运行中 item 的进度条。
`0.1.16` 增加内置 Provider 支持，通用市场 Provider 可以随 Status Hub 打包，定制 Provider 继续通过 GitHub 安装。
`0.1.17` 增加内置 Local Services Provider，用于本地开发运行状态检查。

## UI

菜单栏弹窗默认打开 **总览**：

- 总览：整体 Hub 状态和紧凑 Provider 摘要。
- 固定 Provider：在设置页或总览里标记为固定的 Provider 会出现在总览旁边，作为一级页面展示详细状态和操作。

设置窗口也是 Hub 视角：

- 总览：已安装 Provider 数量、安装状态、更新状态、本地 Provider 目录和 Finder 快捷入口。
- 已安装：Provider 自己声明的配置表单。
- 市场：可搜索的市场。
- GitHub：从仓库 URL 安装插件。

## 市场

市场只列通用 Provider。部分条目随 Status Hub 打包，可以不依赖 GitHub 仓库直接启用。团队定制插件，例如 GitLab monitor 或 Intelli 自动化 Provider，应该通过 GitHub 页安装，而不是固定在市场里。

当前市场 Provider：

- Mac System：内置 CPU、内存、网络、电池、磁盘和温度状态。
- Local Services：内置本机端口、HTTP endpoint、进程和开发运行状态。

## GitHub 插件安装

打开 Status Hub 设置，切换到 **插件 > GitHub**，粘贴 GitHub URL 后点击安装。App 会将仓库 clone 或 pull 到：

```text
~/Library/Application Support/StatusHub/plugins/
```

每个插件仓库根目录必须提供以下文件。完整 schema 见 [docs/provider-standard.md](docs/provider-standard.md)。

```text
statushub-plugin.json
```

插件 manifest 示例：

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

`providers[].icon` 是必填项。它可以是有效的 SF Symbol 名称，也可以是插件相对路径图片，例如 `assets/gitlab-icon.svg`。

如果声明了 `command`，Status Hub 会启动该命令并传入：

- `STATUS_HUB_PROVIDER_ID`
- `STATUS_HUB_STATUS_FILE`
- `STATUS_HUB_CONFIG_FILE`
- `STATUS_HUB_DATA_DIR`

Provider 命令应保持运行，并原子写入状态文件。Status Hub 不会把插件代码加载到 App 进程里；插件只通过状态文件通信。

外部 Provider 注册和状态文件细节见 [docs/provider-standard.md](docs/provider-standard.md)。

## 构建

生成 Xcode 工程：

```bash
xcodegen generate
```

构建：

```bash
xcodebuild -project StatusHub.xcodeproj -scheme StatusHub -destination 'platform=macOS' build
```

运行测试：

```bash
xcodebuild test -project StatusHub.xcodeproj -scheme StatusHub -destination 'platform=macOS'
```
