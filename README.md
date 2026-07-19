# Codex 琪亚娜增强桌宠

为 Windows 版 Codex 制作的非官方琪亚娜同人桌宠增强包。它只增强桌宠动作，不修改 Codex 背景、输入框、图标或其他界面样式，也不会替换 `WindowsApps`、`app.asar` 或应用签名。

> 本项目与 OpenAI、米哈游及 HoYoverse 无隶属、授权或背书关系。

[下载最新版本](https://github.com/3073717189/Codex-Kiana-Pet-Enhancer/releases/latest)

## 功能

- Codex 工作时自动切换奔跑动作，多任务状态会合并判断
- 鼠标视线跟随
- 待机随机彩蛋
- 拖动时保留 Codex 原生拖拽动作
- 审核、等待和失败状态使用对应动画
- 失败动画减速播放并停留末帧，避免突兀循环
- 完整安装与卸载，已有同名桌宠会先备份
- 只增强桌宠，不启用或安装 Codex 主题皮肤

## 系统要求

- Windows 10/11 x64
- 微软商店安装的官方 Codex
- 不需要管理员权限
- 不需要预装 Git、Node.js 或 PowerShell 7

## 安装

1. 从 [Releases](https://github.com/3073717189/Codex-Kiana-Pet-Enhancer/releases/latest) 下载 `Codex-Kiana-Pet-Enhancer-v1.0.0-win-x64.zip`。
2. 完整解压 ZIP，不要在压缩包预览界面中直接运行。
3. 完全退出所有 Codex 窗口。
4. 双击 `安装 Codex 琪亚娜增强桌宠.cmd`。
5. 正常启动官方 Codex。
6. 打开 `设置 > Pets`，刷新自定义桌宠并手动选择“时砾逐光”。
7. 完全退出 Codex。
8. 此后使用桌面或开始菜单中的“Codex 琪亚娜桌宠”启动。

普通 Codex 快捷方式仍可使用，但通过它启动时不会加载增强动作。

## 卸载

1. 完全退出所有 Codex 窗口。
2. 使用桌面或开始菜单中的“卸载 Codex 琪亚娜桌宠”，也可以运行压缩包中的卸载文件。
3. 如果安装前已有同名桌宠，卸载器会恢复原文件。
4. 如果安装后手动修改过桌宠文件，卸载器会保留文件，避免误删。

## 校验下载

Release 页面会同时提供 `.sha256.txt`。可以在 PowerShell 中运行：

```powershell
Get-FileHash '.\Codex-Kiana-Pet-Enhancer-v1.0.0-win-x64.zip' -Algorithm SHA256
```

结果应与 Release 页面公布的 SHA-256 完全一致。

## 工作原理与安全边界

增强器通过仅监听 `127.0.0.1` 的 Chromium DevTools Protocol 会话连接官方 Codex，并在运行时加入桌宠状态逻辑。

它不会修改：

- `WindowsApps`
- `app.asar`
- Codex 应用签名
- `.codex\config.toml`

增强器不会主动上传聊天、项目、用户名、登录信息或 API Key。Chromium 调试端口本身没有同一 Windows 用户下的进程认证；运行增强版 Codex 时，请不要同时运行不可信的本地程序。详见 [SECURITY.md](./SECURITY.md)。

## 已知限制

- Codex 更新后，界面结构或桌宠接口可能变化，需要重新适配。
- 当前仅测试 Windows x64 微软商店版 Codex。
- 启动器和安装脚本没有商业代码签名，Windows 可能显示信誉提示。只从本仓库 Releases 下载并核对 SHA-256。

## 开发与构建

开发环境需要 Node.js 22 或更高版本。发布脚本会下载官方 Node.js Windows x64 压缩包，依据 Node.js 官方 `SHASUMS256.txt` 校验后，仅将运行所需文件和完整许可文本放入发布 ZIP。

```powershell
node --check .\scripts\pet-injector.mjs
node --check .\assets\pet-enhancer.js
node .\tests\pet-enhancer.test.mjs
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-pet-enhancer-release.ps1
```

不要把构建后的 ZIP、Node.js 二进制、测试截图、生成中间素材或本机备份提交到 Git。

## 许可证与素材

- 软件代码：MIT License，见 [LICENSE](./LICENSE)
- 上游代码和 Node.js：见 [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)
- 琪亚娜桌宠图集：不属于 MIT 代码许可，仅供个人非商业同人使用，见 [ASSETS.md](./ASSETS.md)

## 来源与致谢

本项目的 Windows 本机回环 CDP 注入、官方应用发现、启动、恢复及生命周期管理代码，基于并改编自 [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin)，集成基线为 `d80a3bcd6750e7581e57b0460de050a8f6ad9a96`。

上游代码依据 MIT License 使用，并保留原版权和许可声明。本项目是独立的纯桌宠衍生实现，上游作者没有参与或背书本项目。
