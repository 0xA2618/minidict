import Foundation
import SwiftUI
import Carbon.HIToolbox
import AppKit
import ServiceManagement

struct ShortcutConfig: Codable, Equatable {
    var modifier: UInt32
    var keyCode: UInt32
}

struct OpenAIConfig: Codable, Equatable {
    var url: String = "https://api.openai.com/v1/chat/completions"
    var apiKey: String = ""
    var model: String = "gpt-4o-mini"
}

struct YoudaoConfig: Codable, Equatable {
    var appKey: String = ""
    var appSecret: String = ""
}

enum TranslationEngine: String, Codable, CaseIterable {
    case myMemory = "MyMemory (免费内置)"
    case openAI = "自定义 AI 大模型 (需填 Key)"
    case youdao = "有道智云翻译 (需填 Key)"
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var selectionShortcut: ShortcutConfig { didSet { save() } }
    @Published var inputShortcut: ShortcutConfig { didSet { save() } }
    @Published var ocrShortcut: ShortcutConfig { didSet { save() } }
    @Published var clipboardShortcut: ShortcutConfig { didSet { save() } }
    
    @Published var engine: TranslationEngine { didSet { save() } }
    @Published var openAIConfig: OpenAIConfig { didSet { save() } }
    @Published var youdaoConfig: YoudaoConfig { didSet { save() } }
    @Published var launchAtLogin: Bool { didSet { save(); updateLaunchAtLogin() } }
    
    @Published var englishVoice: String { didSet { save() } }
    @Published var chineseVoice: String { didSet { save() } }
    
    private let selectionKey = "shortcut_selection"
    private let inputKey = "shortcut_input"
    private let ocrKey = "shortcut_ocr"
    private let clipboardKey = "shortcut_clipboard"
    private let engineKey = "engine_type"
    private let openaiKey = "openai_config"
    private let youdaoKey = "youdao_config"
    private let launchAtLoginKey = "launch_at_login"
    private let enVoiceKey = "enVoiceIdentifier"
    private let zhVoiceKey = "zhVoiceIdentifier"
    
    var onShortcutsChanged: (() -> Void)?
    
    private init() {
        let defaults = UserDefaults.standard
        
        if let data = defaults.data(forKey: selectionKey), let conf = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
            selectionShortcut = conf
        } else {
            selectionShortcut = ShortcutConfig(modifier: UInt32(optionKey), keyCode: UInt32(kVK_ANSI_D))
        }
        
        if let data = defaults.data(forKey: inputKey), let conf = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
            inputShortcut = conf
        } else {
            inputShortcut = ShortcutConfig(modifier: UInt32(optionKey), keyCode: UInt32(kVK_ANSI_A))
        }
        
        if let data = defaults.data(forKey: ocrKey), let conf = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
            ocrShortcut = conf
        } else {
            ocrShortcut = ShortcutConfig(modifier: UInt32(optionKey), keyCode: UInt32(kVK_ANSI_S))
        }
        
        if let data = defaults.data(forKey: clipboardKey), let conf = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
            clipboardShortcut = conf
        } else {
            clipboardShortcut = ShortcutConfig(modifier: UInt32(cmdKey | shiftKey), keyCode: 8)
        }
        
        if let data = defaults.string(forKey: engineKey), let e = TranslationEngine(rawValue: data) {
            engine = e
        } else {
            engine = .myMemory
        }
        
        if let data = defaults.data(forKey: openaiKey), var conf = try? JSONDecoder().decode(OpenAIConfig.self, from: data) {
            if conf.apiKey.isEmpty {
                conf.url = "https://api.openai.com/v1/chat/completions"
                conf.apiKey = ""
                conf.model = "gpt-4o-mini"
            }
            openAIConfig = conf
        } else {
            openAIConfig = OpenAIConfig()
        }
        
        if let data = defaults.data(forKey: youdaoKey), let conf = try? JSONDecoder().decode(YoudaoConfig.self, from: data) {
            youdaoConfig = conf
        } else {
            youdaoConfig = YoudaoConfig()
        }
        
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLogin = defaults.bool(forKey: launchAtLoginKey)
        }
        
        englishVoice = defaults.string(forKey: enVoiceKey) ?? "edge_tts"
        chineseVoice = defaults.string(forKey: zhVoiceKey) ?? "edge_tts"
    }
    
    private func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            if launchAtLogin {
                if service.status != .enabled {
                    do {
                        try service.register()
                    } catch {
                        NSLog("[MiniDict] 注册开机自启失败: \(error)")
                    }
                }
            } else {
                if service.status == .enabled {
                    do {
                        try service.unregister()
                    } catch {
                        NSLog("[MiniDict] 注销开机自启失败: \(error)")
                    }
                }
            }
        }
    }
    
    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(selectionShortcut) { defaults.set(data, forKey: selectionKey) }
        if let data = try? JSONEncoder().encode(inputShortcut) { defaults.set(data, forKey: inputKey) }
        if let data = try? JSONEncoder().encode(ocrShortcut) { defaults.set(data, forKey: ocrKey) }
        if let data = try? JSONEncoder().encode(clipboardShortcut) { defaults.set(data, forKey: clipboardKey) }
        
        defaults.set(engine.rawValue, forKey: engineKey)
        if let data = try? JSONEncoder().encode(openAIConfig) { defaults.set(data, forKey: openaiKey) }
        if let data = try? JSONEncoder().encode(youdaoConfig) { defaults.set(data, forKey: youdaoKey) }
        defaults.set(launchAtLogin, forKey: launchAtLoginKey)
        
        defaults.set(englishVoice, forKey: enVoiceKey)
        defaults.set(chineseVoice, forKey: zhVoiceKey)
        
        onShortcutsChanged?()
    }
}

let keyCodes: [(String, UInt32)] = [
    ("A", UInt32(kVK_ANSI_A)), ("B", UInt32(kVK_ANSI_B)), ("C", UInt32(kVK_ANSI_C)),
    ("D", UInt32(kVK_ANSI_D)), ("E", UInt32(kVK_ANSI_E)), ("F", UInt32(kVK_ANSI_F)),
    ("G", UInt32(kVK_ANSI_G)), ("H", UInt32(kVK_ANSI_H)), ("I", UInt32(kVK_ANSI_I)),
    ("J", UInt32(kVK_ANSI_J)), ("K", UInt32(kVK_ANSI_K)), ("L", UInt32(kVK_ANSI_L)),
    ("M", UInt32(kVK_ANSI_M)), ("N", UInt32(kVK_ANSI_N)), ("O", UInt32(kVK_ANSI_O)),
    ("P", UInt32(kVK_ANSI_P)), ("Q", UInt32(kVK_ANSI_Q)), ("R", UInt32(kVK_ANSI_R)),
    ("S", UInt32(kVK_ANSI_S)), ("T", UInt32(kVK_ANSI_T)), ("U", UInt32(kVK_ANSI_U)),
    ("V", UInt32(kVK_ANSI_V)), ("W", UInt32(kVK_ANSI_W)), ("X", UInt32(kVK_ANSI_X)),
    ("Y", UInt32(kVK_ANSI_Y)), ("Z", UInt32(kVK_ANSI_Z)),
    ("1", UInt32(kVK_ANSI_1)), ("2", UInt32(kVK_ANSI_2)), ("3", UInt32(kVK_ANSI_3)),
    ("4", UInt32(kVK_ANSI_4)), ("5", UInt32(kVK_ANSI_5)), ("6", UInt32(kVK_ANSI_6)),
    ("7", UInt32(kVK_ANSI_7)), ("8", UInt32(kVK_ANSI_8)), ("9", UInt32(kVK_ANSI_9)),
    ("0", UInt32(kVK_ANSI_0))
]

struct ShortcutPickerView: View {
    let title: String
    @Binding var config: ShortcutConfig
    
    var body: some View {
        HStack {
            Text(title).frame(width: 80, alignment: .leading)
            Picker("", selection: $config.modifier) {
                Text("Option (⌥)").tag(UInt32(optionKey))
                Text("Command (⌘)").tag(UInt32(cmdKey))
                Text("Control (⌃)").tag(UInt32(controlKey))
                Text("Shift+Option").tag(UInt32(optionKey | shiftKey))
                Text("Shift+Command").tag(UInt32(cmdKey | shiftKey))
                Text("Ctrl+Option").tag(UInt32(controlKey | optionKey))
                Text("Ctrl+Command").tag(UInt32(controlKey | cmdKey))
            }
            .frame(width: 150)
            
            Picker("", selection: $config.keyCode) {
                ForEach(keyCodes, id: \.1) { (name, code) in
                    Text(name).tag(code)
                }
            }
            .frame(width: 80)
        }
        .padding(.vertical, 4)
    }
}

struct SettingsView: View {
    @ObservedObject var vm = SettingsManager.shared
    
    var body: some View {
        TabView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    ShortcutPickerView(title: "划词翻译", config: $vm.selectionShortcut)
                    ShortcutPickerView(title: "输入翻译", config: $vm.inputShortcut)
                    ShortcutPickerView(title: "截图 OCR", config: $vm.ocrShortcut)
                    ShortcutPickerView(title: "剪贴板历史", config: $vm.clipboardShortcut)
                }
                Spacer()
            }
            .padding(24)
            .tabItem { Text("快捷键") }
            
            VStack(alignment: .leading, spacing: 16) {
                Picker("翻译引擎", selection: $vm.engine) {
                    ForEach(TranslationEngine.allCases, id: \.self) { e in
                        Text(e.rawValue).tag(e)
                    }
                }
                .pickerStyle(.radioGroup)
                
                if vm.engine == .openAI {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("API 接口:").frame(width: 80, alignment: .trailing)
                            TextField("https://api.openai.com/v1/chat/completions", text: $vm.openAIConfig.url)
                        }
                        HStack {
                            Text("API Key:").frame(width: 80, alignment: .trailing)
                            SecureField("sk-xxxxxxxx", text: $vm.openAIConfig.apiKey)
                        }
                        HStack {
                            Text("模型:").frame(width: 80, alignment: .trailing)
                            TextField("gpt-4o-mini", text: $vm.openAIConfig.model)
                        }
                        Text("支持任何兼容 OpenAI 格式的大模型接口（如 DeepSeek, 豆包, 阿里等）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 88)
                    }
                }
                
                if vm.engine == .youdao {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("应用 ID:").frame(width: 80, alignment: .trailing)
                            TextField("有道智云 AppKey", text: $vm.youdaoConfig.appKey)
                        }
                        HStack {
                            Text("应用密钥:").frame(width: 80, alignment: .trailing)
                            SecureField("有道智云 AppSecret", text: $vm.youdaoConfig.appSecret)
                        }
                        Text("需要注册有道智云并开通“文本翻译”服务获取 AppKey 和 AppSecret。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 88)
                    }
                }
                
                Divider()
                Toggle("开机自动启动", isOn: $vm.launchAtLogin)
                Spacer()
            }
            .padding(24)
            .tabItem { Text("翻译设置") }
            
            VStack(alignment: .leading, spacing: 16) {
                Picker("英文发音", selection: $vm.englishVoice) {
                    ForEach(Speaker.shared.englishVoices(), id: \.self) { id in
                        Text(Speaker.shared.displayName(for: id)).tag(id)
                    }
                }
                
                Picker("中文发音", selection: $vm.chineseVoice) {
                    ForEach(Speaker.shared.chineseVoices(), id: \.self) { id in
                        Text(Speaker.shared.displayName(for: id)).tag(id)
                    }
                }
                
                Text("“微软 Edge 神经网络音色”需要保持电脑联网，音质最接近真人。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(24)
            .tabItem { Text("发音设置") }
        }
        .frame(width: 450, height: 300)
    }
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    
    init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "MiniDict 设置"
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: SettingsView())
        
        super.init(window: win)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}