import AppKit
import ApplicationServices
import CoreGraphics

enum Permissions {
    static func isAXTrusted() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func requestAX() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func isScreenRecordingGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    static func openSettings(privacyPane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(privacyPane)") {
            NSWorkspace.shared.open(url)
        }
    }

    static func ensureAX() -> Bool {
        if isAXTrusted() { return true }
        let alert = NSAlert()
        alert.messageText = "需要「辅助功能」权限"
        alert.informativeText = "划词翻译需要模拟 ⌘C 读取选中文本。请打开系统设置，在「隐私与安全性 → 辅助功能」中勾选 MiniDict，然后重试。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            requestAX()
            openSettings(privacyPane: "Privacy_Accessibility")
        }
        return isAXTrusted()
    }

    static func ensureScreenRecording() -> Bool {
        if isScreenRecordingGranted() { return true }
        let alert = NSAlert()
        alert.messageText = "需要「屏幕录制」权限"
        alert.informativeText = "截图 OCR 需要读取屏幕内容。请打开系统设置，在「隐私与安全性 → 屏幕录制」中勾选 MiniDict（可能需要重启 MiniDict 后生效）。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            requestScreenRecording()
            openSettings(privacyPane: "Privacy_ScreenCapture")
        }
        return isScreenRecordingGranted()
    }
}
