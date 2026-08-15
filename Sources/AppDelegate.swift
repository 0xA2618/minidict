import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var permissionItem: NSMenuItem?
    private let overlay = CaptureOverlay()
    private var ocrInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        _ = DictionaryStore.shared
        ClipboardTracker.shared.start()
        TranslationWindowController.shared.onTranslate = { [weak self] text in
            self?.performTranslation(text)
        }
        setupStatusItem()
        setupHotKeys()
        SettingsManager.shared.onShortcutsChanged = { [weak self] in
            self?.setupHotKeys()
        }
        refreshPermissionStatus()
        proactivelyRequestPermissions()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        NSApp.mainMenu = mainMenu
    }

    private func proactivelyRequestPermissions() {
        let defaults = UserDefaults.standard
        if !Permissions.isAXTrusted(), !defaults.bool(forKey: "didPromptAX") {
            defaults.set(true, forKey: "didPromptAX")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Permissions.requestAX()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            let img = NSImage(systemSymbolName: "character.book.closed.fill",
                              accessibilityDescription: "MiniDict")
            img?.isTemplate = true
            btn.image = img
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "划词翻译  ⌥D", action: #selector(actionSelection), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "输入翻译  ⌥A", action: #selector(actionInput), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "截图 OCR  ⌥S", action: #selector(actionOCR), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "剪贴板历史  ⌘⇧C", action: #selector(actionClipboardHistory), keyEquivalent: ""))
        menu.addItem(.separator())
        let perm = NSMenuItem(title: "权限：检查中…", action: nil, keyEquivalent: "")
        perm.isEnabled = false
        permissionItem = perm
        menu.addItem(perm)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ","))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 MiniDict", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    
    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    private func refreshPermissionStatus() {
        let ax = Permissions.isAXTrusted() ? "✓" : "✗"
        let sr = Permissions.isScreenRecordingGranted() ? "✓" : "✗"
        permissionItem?.title = "辅助功能 \(ax)   屏幕录制 \(sr)"
    }

    private func setupHotKeys() {
        let sm = SettingsManager.shared
        HotKeyManager.shared.unregisterAll()
        
        HotKeyManager.shared.register(keyCode: sm.selectionShortcut.keyCode, modifiers: sm.selectionShortcut.modifier, id: 1) { [weak self] in
            self?.actionSelection()
        }
        HotKeyManager.shared.register(keyCode: sm.inputShortcut.keyCode, modifiers: sm.inputShortcut.modifier, id: 2) { [weak self] in
            self?.actionInput()
        }
        HotKeyManager.shared.register(keyCode: sm.ocrShortcut.keyCode, modifiers: sm.ocrShortcut.modifier, id: 3) { [weak self] in
            self?.actionOCR()
        }
        HotKeyManager.shared.register(keyCode: sm.clipboardShortcut.keyCode, modifiers: sm.clipboardShortcut.modifier, id: 4) { [weak self] in
            self?.actionClipboardHistory()
        }
    }

    @objc private func actionSelection() {
        AppFocusManager.shared.recordFrontmostApp()
        refreshPermissionStatus()
        guard Permissions.ensureAX() else { return }
        SelectionGrabber.shared.grab { [weak self] text in
            DispatchQueue.main.async {
                self?.refreshPermissionStatus()
                guard let t = text else {
                    TranslationWindowController.shared.showWindowWithText("未获取到选中的文本", autoTranslate: false)
                    return
                }
                TranslationWindowController.shared.showWindowWithText(t, autoTranslate: true)
            }
        }
    }

    @objc private func actionInput() {
        AppFocusManager.shared.recordFrontmostApp()
        refreshPermissionStatus()
        TranslationWindowController.shared.showWindowWithText("", autoTranslate: false)
    }

    @objc private func actionOCR() {
        AppFocusManager.shared.recordFrontmostApp()
        refreshPermissionStatus()
        guard !ocrInProgress else { return }
        guard Permissions.ensureScreenRecording() else { return }
        ocrInProgress = true
        overlay.begin { [weak self] rect in
            self?.ocrInProgress = false
            if rect == .zero { return }
            guard let screen = NSScreen.main,
                  let img = OCRService.shared.capture(rect: rect, screen: screen) else {
                TranslationWindowController.shared.showWindowWithText("截图失败", autoTranslate: false)
                return
            }
            TranslationWindowController.shared.showWindowWithText("识别中…", autoTranslate: false)
            OCRService.shared.recognize(image: img) { text in
                DispatchQueue.main.async {
                    guard let t = text,
                          !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        TranslationWindowController.shared.showWindowWithText("未识别到文字", autoTranslate: false)
                        return
                    }
                    TranslationWindowController.shared.showWindowWithText(t, autoTranslate: true)
                }
            }
        }
    }

    @objc private func actionClipboardHistory() {
        AppFocusManager.shared.recordFrontmostApp()
        ClipboardHistoryWindowController.shared.show()
    }

    private func performTranslation(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let dict = DictionaryStore.shared

        if !containsChinese(trimmed) {
            let words = englishTokens(in: trimmed)
            let hasSpace = trimmed.contains(" ")
            let isSingleWord = (words.count == 1) && !hasSpace
            
            if isSingleWord {
                let e = dict.lookup(words[0].lowercased())
                let card = e != nil ? parseDictCard(word: words[0], e: e!) : nil
                TranslationWindowController.shared.setResult(original: trimmed, ipa: nil, translation: nil, card: card)
                
                if SettingsManager.shared.engine == .openAI {
                    TranslationWindowController.shared.setStatus("AI 润色中…")
                    Translator.shared.translate(trimmed, sourceIsChinese: false) { r in
                        DispatchQueue.main.async {
                            switch r {
                            case .success(let t): TranslationWindowController.shared.setTranslation(t, source: Translator.shared.currentEngineName)
                            case .failure: TranslationWindowController.shared.setStatus(nil)
                            }
                        }
                    }
                }
            } else {
                TranslationWindowController.shared.setResult(original: trimmed, ipa: nil, translation: nil, card: nil)
                TranslationWindowController.shared.setStatus("翻译中…")
                Translator.shared.translate(trimmed, sourceIsChinese: false) { r in
                    DispatchQueue.main.async {
                        switch r {
                        case .success(let t): TranslationWindowController.shared.setTranslation(t, source: Translator.shared.currentEngineName)
                        case .failure(let err): TranslationWindowController.shared.setStatus("翻译失败（\(err.localizedDescription)）")
                        }
                    }
                }
            }
        } else {
            TranslationWindowController.shared.setResult(original: trimmed, ipa: nil, translation: nil, card: nil)
            TranslationWindowController.shared.setStatus("翻译中…")
            Translator.shared.translate(trimmed, sourceIsChinese: true) { r in
                DispatchQueue.main.async {
                    switch r {
                    case .success(let en):
                        TranslationWindowController.shared.setTranslation(en, source: Translator.shared.currentEngineName)
                    case .failure(let err): TranslationWindowController.shared.setStatus("翻译失败（\(err.localizedDescription)）")
                    }
                }
            }
        }
    }
}
