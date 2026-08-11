# MiniDict (本地极简词典与翻译工具)
One translation software supports copy history

## 项目背景
本项目最初源于用户希望在 macOS 上实现一个能在查词时自动显示英美双音标的本地翻译工具（因为原先使用的 Bob 商店版需要收费会员）。随着功能的逐步迭代，它最终演变成了一个**功能完整、全免费、不依赖任何商业授权**的 macOS 菜单栏级应用。

## 核心功能
1. **多模式取词与翻译**：
   - **`⌥D` (划词翻译)**：自动模拟 `Cmd+C` 获取选中文本或剪贴板内容，并立刻进行翻译。
   - **`⌥A` (输入翻译)**：呼出常驻主窗口，提供多行输入，支持 `Cmd+Enter` 快速翻译。
   - **`⌥S` (截图 OCR)**：呼出自定义截屏选区，利用 macOS 原生 `Vision` 框架进行完全离线的精准文字识别。

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
- **构建方式**：通过 `build.sh` 直接使用 `swiftc` 命令行编译打包，无需繁重的 Xcode 工程文件，且内置了生成自签名证书的逻辑以绕过 macOS 的权限重置痛点。

## 未来维护指南
- 代码位于 `Sources/` 目录下，包含 `AppDelegate.swift`, `UI.swift`, `Settings.swift`, `Services.swift`, `Speaker.swift` 等模块。
- 每次修改代码后，直接运行 `./build.sh` 即可重新编译并启动应用。
