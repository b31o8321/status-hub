# Status Hub 安装说明

Status Hub 当前没有 Apple Developer ID 签名和公证。首次安装时，macOS 可能会拦截打开。

## 安装

1. 打开 DMG。
2. 将 `StatusHub.app` 拖到 `Applications`。
3. 在终端执行：

```bash
xattr -dr com.apple.quarantine /Applications/StatusHub.app
```

如果提示权限不足，执行：

```bash
sudo xattr -dr com.apple.quarantine /Applications/StatusHub.app
```

4. 打开 `/Applications/StatusHub.app`。

## 为什么需要执行命令

这是未签名、未公证 macOS App 的 Gatekeeper 限制。`xattr` 命令只移除这个 App 的下载隔离标记，不会关闭系统安全设置。

后续如果启用 Apple Developer ID 签名和 notarization，就不再需要这一步。

