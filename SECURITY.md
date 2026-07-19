# Security Policy

## 支持范围

目前只维护最新 GitHub Release。旧版本发现问题后应先升级复现。

## 运行时安全模型

本项目：

- 只支持微软商店安装的官方 Windows Codex
- 通过官方应用标识启动 Codex
- 不替换或修改 `WindowsApps`、`app.asar` 或应用签名
- 不需要管理员权限
- 不修改 `.codex\config.toml`
- 不主动上传聊天、项目、用户名、登录信息或 API Key
- 将运行状态保存到当前用户的 `%LOCALAPPDATA%\CodexKianaPet`
- 将桌宠安装到当前用户的 `%USERPROFILE%\.codex\pets\time-runner-kiana`

增强器会开启仅监听 `127.0.0.1` 的 Chromium 调试会话。该接口不会暴露到局域网，但 Chromium CDP 没有同一 Windows 用户下的进程认证。运行增强版 Codex 时，其他同用户本地进程理论上能够尝试连接调试端口。

请勿在增强版 Codex 运行期间执行来源不明的软件或脚本。

## 下载安全

- 只从本仓库 GitHub Releases 下载
- 完整解压后再运行安装器
- 使用随 Release 提供的 SHA-256 文件校验 ZIP
- 校验不一致时不要运行
- 发布包内置的 Node.js 来自 Node.js 官方下载地址，并在构建时校验官方 SHA-256

安装器和启动器当前没有商业代码签名。Windows 信誉提示不代表文件一定有害，也不能替代哈希校验。

## 报告安全问题

请优先使用 GitHub 的私有 Security Advisory 报告安全问题。不要在公开 Issue 中提交：

- Token、Cookie、登录信息
- 聊天或项目内容
- 用户名和本机绝对路径
- 可直接利用的未修复漏洞细节

报告中请包含版本号、Windows 版本、Codex 版本、复现步骤和脱敏日志。
