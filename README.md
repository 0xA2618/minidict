# MiniDict (本地极简词典与翻译工具)
One translation software supports copy history

## 下载安装

> 支持 **Apple Silicon (M 系列)** 与 **Intel** 两种芯片的 Mac，要求 macOS 15.0 及以上。

1. 前往 [Releases](https://github.com/0xA2618/minidict/releases) 页面。
2. 下载最新的 `MiniDict-x.y.z-universal.zip`。
3. 解压后将 `MiniDict.app` 拖入「应用程序」文件夹。
4. 首次打开（见下方说明）。

### ⚠️ 首次打开提示"无法验证开发者"怎么办

MiniDict 采用**自签名**发布（未加入 Apple Developer 付费计划），macOS 的 Gatekeeper 会拦截未公证的应用。**这不是病毒或损坏，** 按以下任一方式即可正常打开：

**方式一：右键打开（推荐）**
1. 在「应用程序」中找到 `MiniDict.app`，**右键**点击它。
2. 选择菜单中的「**打开**」。
3. 在弹出的对话框中点击「**打开**」。
4. 之后即可像普通应用一样双击打开。

**方式二：命令行解除隔离属性**
```bash
xattr -cr /Applications/MiniDict.app
```
执行后双击即可直接打开。

> 💡 提示：`xattr -cr` 会移除下载文件的"隔离"标记（com.apple.quarantine），仅对你自己信任的应用使用此命令。

## 项目背景
本项目最初源于用户希望在 macOS 上实现一个能在查词时自动显示英美双音标的本地翻译工具（因为原先使用的 Bob 商店版需要收费会员）。随着功能的逐步迭代，它最终演变成了一个**功能完整、全免费、不依赖任何商业授权**的 macOS 菜单栏级应用。

## 核心功能
1. **多模式取词与翻译**：
   - **`⌥D` (划词翻译)**：自动模拟 `Cmd+C` 获取选中文本或剪贴板内容，并立刻进行翻译。
   - **`⌥A` (输入翻译)**：呼出常驻主窗口，提供多行输入，支持 `Cmd+Enter` 快速翻译。
   - **`⌥S` (截图 OCR)**：呼出自定义截屏选区，利用 macOS 原生 `Vision` 框架进行完全离线的精准文字识别。
   - **`⌘⇧C` (剪贴板历史)**：呼出剪贴板历史面板，自动记录最近 50 条复制内容，支持关键词**搜索过滤**，通过 `↑↓` 选择、`Enter` 选中复制入剪贴板并自动切回原窗口焦点，可随时 `⌘V` 手动粘贴，`Esc` 关闭。

2. **本地优先的查词体验**：
   - 当用户查询**单个英文单词**时，应用会完全离线地访问内置的 SQLite 词典数据库（包含 14.7 万条 ECDICT 与 ipa-dict 词库）。
   - 结果会以极美的 SwiftUI 卡片形式展示，包含美/英双音标、词性释义、以及复数/过去式等变形标签。

3. **智能长句翻译**：
   - 长句或中文输入时，自动屏蔽单个单词的音标，转为纯净的翻译模式。
   - 默认使用极其稳定的 **MyMemory 免费 API**。
   - 支持在设置中无缝切换为**自定义 AI 大模型**（如 OpenAI、DeepSeek、豆包等）。

4. **高级发音系统 (TTS)**：
   - 集成了系统原生的优质发音（如 macOS 15 最新的 Sandy、Tingting 音色）。
   - 内置了调用 **微软 Edge 神经网络语音 (Edge TTS)** 的逻辑，通过调用本地环境安装好的 Python 库实现媲美字节豆包等云端大厂的极度自然发音。

## 技术栈与架构
- **语言**：Swift (Swift 5/6), 纯代码，无 storyboard。
- **UI 层**：核心主界面 (`TranslationMainView`) 和设置界面 (`SettingsView`) 使用 **SwiftUI** 开发，兼顾现代化与流畅度。全局窗口容器、截图覆盖层则使用传统的 **AppKit** (`NSWindow`, `NSPanel`) 以实现无边框悬浮和精确控制。
- **底层支持**：
  - `Carbon.HIToolbox` 用于注册全局快捷键 (Global Hotkeys)。
  - `Vision` 框架处理图片到文本的 OCR。
  - `SQLite3` 极速查询本地 10M+ 的词库。
  - `AVFoundation` 和 `NSSpeechSynthesizer` 进行多引擎音频播放。
- **构建方式**：通过 `build.sh` 直接使用 `swiftc` 命令行编译打包，无需繁重的 Xcode 工程文件，且内置了生成自签名证书的逻辑以绕过 macOS 的权限重置痛点。`build.sh` 会同时编译 **Apple Silicon (arm64)** 与 **Intel (x86_64)** 两个版本并通过 `lipo` 合并为 Universal 二进制。

## 未来维护指南
- 代码位于 `Sources/` 目录下，包含 `AppDelegate.swift`, `UI.swift`, `Settings.swift`, `Services.swift`, `Speaker.swift` 等模块。
- 每次修改代码后，直接运行 `./build.sh` 即可重新编译并启动应用。
