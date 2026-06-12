# 更新日志

[English](CHANGELOG.en.md)

## 0.1.17

- 新增内置 Local Services Provider，用于本机端口、HTTP endpoint、进程和开发运行状态检查。
- Provider 配置页支持 `textarea` 多行字段编辑。

## 0.1.16

- 新增内置 Provider 支持，用于通用市场 Provider。
- Mac System 改为内置 Provider 资源，新用户不再需要单独从 GitHub 安装。
- GitHub 安装机制继续用于团队定制 Provider。

## 0.1.15

- 将文档类专用链接文案改为通用 Provider 链接。
- Provider 详情 item 支持直接打开按钮和进度条。

## 0.1.14

- 插件更新可以从脏工作区恢复。
- 强制刷新插件代码时保留 Provider `runtime/` 数据。

## 0.1.13

- 增加 Provider 自有外部配置 helper，用于复杂设置流程。
- 将 `externalConfig` 字段渲染为操作按钮，而不是可编辑 JSON。

## 0.1.12

- 增加 GitHub Actions DMG 打包，并补充未签名 App 安装说明。
- 增加 Provider 实现标准文档。
- 支持插件相对路径图片 icon，例如 SVG 文件。

## 0.1.11

- 要求 Provider manifest 声明 icon。
- 固定 Provider 导航改为紧凑纯图标 tabs。

## 0.1.10

- 限制紧凑总览菜单和任务卡片里的 Provider 输出链接数量。

## 0.1.9

- 将 Provider item actions 放到 item 状态旁边的紧凑图标按钮里。

## 0.1.8

- 长日志路径不再内联展示在任务卡片中，改为“打开日志目录”的 Finder 快捷入口。

## 0.1.7

- 安装或更新 GitHub 插件时保留 Provider `runtime/` 数据，包括本地配置。

## 0.1.4

- 设置页新增总览，展示 Provider 安装数量、更新状态、全部更新和 Finder 快捷入口。
- 将 Provider 自有配置移到可折叠的已安装 Provider 区块中。
- 恢复菜单弹窗里的固定 Provider 一级页面，同时保持总览紧凑。
- 菜单弹窗使用 macOS material 背景。

## 0.1.3

- 新增 Provider item actions，Provider 可以暴露手动触发和开关按钮。
- 新增 Provider item links，用于展示近期生成文档和其他快捷链接。
- 主弹窗只渲染面向用户的 Provider 详情。

## 0.1.2

- 将插件管理从主弹窗移到设置页。
- 主弹窗聚焦总览和固定 Provider 页面。
- 支持从已安装 Provider 列表和总览行固定 Provider 为一级展示。
- 按使用频率调整插件管理顺序：已安装、市场、GitHub。

## 0.1.1

- 通过检查最新 Git tag 安装和更新 tagged 插件。
- 只有远端存在更新 tag 时才在市场展示更新。
- Provider metric 详情默认折叠，让多个 Provider 可以同时展示。
- 启动 Provider 命令前清理旧的托管 Provider 进程。

## 0.1.0

初始 Status Hub 版本。

- 重置 App 版本为 `0.1.0` / build `1`。
- App 安装后默认保持空状态。
- 增加第一个市场页面，包含通用 Mac System Provider。
- 支持通过 JSON manifest 注册本地 Provider。
- 支持从 GitHub 仓库安装 Provider 插件。
- 增加插件安装超时处理和部分 clone 清理。
- 启动 Provider manifest 声明的命令。
- 读取 Provider 状态快照 JSON。
- 渲染可选的 Provider item value 和 detail。
- 菜单栏展示 Hub 总览和已安装 Provider 摘要。
- 移除之前单用途 monitor 代码。
