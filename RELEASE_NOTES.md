# Codex 琪亚娜增强桌宠 v1.0.0

首个公开测试版。它是独立的纯桌宠增强包，不安装完整主题，也不修改 Codex 的背景、输入框、图标、`WindowsApps`、`app.asar` 或 `.codex\config.toml`。

## 功能

- Codex 工作时自动奔跑，并合并多个任务的工作状态
- 鼠标视线跟随、待机随机彩蛋和原生拖拽兼容
- 等待、审核与失败状态动画
- 失败动画减速并停留末帧
- 安装、升级和卸载均保留回滚路径；已有同名桌宠会先备份

## 安装

1. 下载并完整解压 `Codex-Kiana-Pet-Enhancer-v1.0.0-win-x64.zip`。
2. 完全退出所有 Codex 窗口。
3. 双击 `安装 Codex 琪亚娜增强桌宠.cmd`。
4. 正常打开官方 Codex，在 `设置 > Pets` 中刷新并手动选择“时砾逐光”。
5. 完全退出 Codex，此后使用桌面或开始菜单中的“Codex 琪亚娜桌宠”启动。

普通 Codex 快捷方式仍然可用，但不会加载增强动作。卸载前也请先完全退出 Codex。

## 下载校验

ZIP SHA-256：

```text
F063902F76DE9A95B23115A64347C41D20BCA735B8DB8CF77499E38E6EA74F86
```

Release 同时附带 `.zip.sha256.txt` 校验文件。

## 使用边界

- Windows 10/11 x64
- 微软商店安装的官方 Codex
- 不需要管理员权限、Git、预装 Node.js 或 PowerShell 7
- 非官方个人同人项目，免费提供；琪亚娜图集仅供个人非商业同人使用

安装与故障说明见仓库 [README](https://github.com/3073717189/Codex-Kiana-Pet-Enhancer#readme)，安全边界见 [SECURITY.md](https://github.com/3073717189/Codex-Kiana-Pet-Enhancer/blob/main/SECURITY.md)，素材与权利声明见 [ASSETS.md](https://github.com/3073717189/Codex-Kiana-Pet-Enhancer/blob/main/ASSETS.md)。
