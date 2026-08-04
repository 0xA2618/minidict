import AppKit

import AppKit
import SwiftUI

class TranslationViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var original: String?
    @Published var ipa: String?
    @Published var translation: String?
    @Published var card: DictCard?
    @Published var status: String?
}

struct TranslationMainView: View {
    @ObservedObject var vm: TranslationViewModel
    var onTranslate: () -> Void
    var onSpeakOriginal: () -> Void
    var onSpeakTranslation: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $vm.inputText)
                .font(.system(size: 16))
                .padding(8)
                .frame(height: 120)
                .background(Color.clear)
            
            HStack {
                if vm.original != nil || vm.card != nil {
                    Button(action: onSpeakOriginal) {
                        Label("朗读原文", systemImage: "speaker.wave.2")
                    }.buttonStyle(.plain).foregroundColor(.blue)
                }
                
                if vm.translation != nil {
                    Button(action: onSpeakTranslation) {
                        Label("朗读译文", systemImage: "speaker.wave.2")
                    }.buttonStyle(.plain).foregroundColor(.blue)
                }
                
                Spacer()
                
                Button("翻译 (Enter)", action: onTranslate)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let s = vm.status {
                        Text(s).foregroundColor(.secondary)
                    }
                    
                    if let card = vm.card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(card.word)
                                    .font(.system(size: 24, weight: .bold, design: .serif))
                                
                                if let ph = card.phonetics {
                                    Text(ph)
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                Button(action: {
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.setString(card.meanings.joined(separator: "\n"), forType: .string)
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("复制释义")
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(card.meanings, id: \.self) { m in
                                    Text(m)
                                        .font(.system(size: 15))
                                }
                            }
                            
                            if !card.exchanges.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(card.exchanges, id: \.self) { ex in
                                            Text(ex)
                                                .font(.system(size: 12))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.15))
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                            }
                        }
                        .textSelection(.enabled)
                    }
                    
                    if vm.translation != nil || vm.ipa != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            if let t = vm.translation {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("翻译").font(.caption).foregroundColor(.secondary)
                                        Spacer()
                                        Button(action: {
                                            let pb = NSPasteboard.general
                                            pb.clearContents()
                                            pb.setString(t, forType: .string)
                                        }) {
                                            Image(systemName: "doc.on.doc")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("复制翻译结果")
                                    }
                                    Text(t).font(.system(size: 15)).textSelection(.enabled)
                                }
                            }
                            if let ipa = vm.ipa {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("音标").font(.caption).foregroundColor(.secondary)
                                    Text(ipa).font(.system(size: 14, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .textSelection(.enabled)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(minWidth: 350, minHeight: 450)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

final class TranslationWindowController: NSWindowController, NSWindowDelegate {
    static let shared = TranslationWindowController()
    
    let vm = TranslationViewModel()
    var onTranslate: ((String) -> Void)?
    
    init() {
        let win = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.backgroundColor = NSColor.windowBackgroundColor
        win.level = .floating
        win.hidesOnDeactivate = true
        win.isFloatingPanel = true
        win.setFrameAutosaveName("TranslationWindow")
        
        super.init(window: win)
        win.delegate = self
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let rootView = TranslationMainView(vm: vm, onTranslate: { [weak self] in
            guard let self = self else { return }
            let text = self.vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            self.onTranslate?(text)
        }, onSpeakOriginal: { [weak self] in
            guard let self = self else { return }
            let text = self.vm.original ?? self.vm.inputText
            Speaker.shared.speak(text, language: containsChinese(text) ? "zh" : "en")
        }, onSpeakTranslation: { [weak self] in
            guard let t = self?.vm.translation else { return }
            Speaker.shared.speak(t, language: containsChinese(t) ? "zh" : "en")
        })
        
        win.contentView = NSHostingView(rootView: rootView)
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            if ev.keyCode == 53, let win = self?.window, win.isVisible {
                win.orderOut(nil)
                Speaker.shared.stop()
                return nil
            }
            
            if ev.keyCode == 36, let win = self?.window, win.isKeyWindow {
                if ev.modifierFlags.contains(.shift) {
                    return ev
                } else if !ev.modifierFlags.contains(.command) && !ev.modifierFlags.contains(.option) && !ev.modifierFlags.contains(.control) {
                    self?.doTranslate()
                    return nil
                }
            }
            return ev
        }
    }
    
    required init?(coder: NSCoder) { fatalError() }

    @objc func doTranslate() {
        let text = vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onTranslate?(text)
    }
    
    func showWindowWithText(_ text: String, autoTranslate: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        window?.hidesOnDeactivate = false
        
        if !(window?.isVisible ?? false) {
            positionNearMouse()
        }
        
        window?.makeKeyAndOrderFront(nil)
        window?.hidesOnDeactivate = true
        
        vm.inputText = text
        if autoTranslate {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                onTranslate?(t)
            }
        }
    }
    
    private func positionNearMouse() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.main, let win = window else { return }
        let vf = screen.visibleFrame
        var p = NSPoint(x: mouse.x - win.frame.width / 2, y: mouse.y - win.frame.height / 2)
        p.x = min(max(p.x, vf.minX + 8), vf.maxX - win.frame.width - 8)
        p.y = min(max(p.y, vf.minY + 8), vf.maxY - win.frame.height - 8)
        win.setFrameOrigin(p)
    }
    
    func setStatus(_ status: String?) {
        vm.status = status
    }
    
    func setResult(original: String, ipa: String?, translation: String?, card: DictCard?) {
        vm.original = original
        vm.ipa = ipa
        vm.translation = translation
        vm.status = nil
        vm.card = card
    }
    
    func setTranslation(_ text: String) {
        vm.translation = text
        vm.status = nil
    }
    
    func setIPA(_ text: String) {
        vm.ipa = text
    }

    func windowDidResignKey(_ notification: Notification) {
        if let win = window, win.hidesOnDeactivate {
            win.orderOut(nil)
            Speaker.shared.stop()
        }
    }
}

// MARK: - 截图选区覆盖层

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
}

final class CaptureOverlay {
    private var window: NSWindow?
    private var escMonitor: Any?
    var onComplete: ((CGRect) -> Void)?

    func begin(onComplete: @escaping (CGRect) -> Void) {
        self.onComplete = onComplete
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let win = OverlayWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = NSColor.clear
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = CaptureOverlayView(frame: NSRect(origin: .zero, size: frame.size))
        view.onDone = { [weak self] rect in
            self?.cancel()
            self?.onComplete?(rect)
        }
        win.contentView = view
        win.setFrameOrigin(frame.origin)

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(view)
        window = win

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            if ev.keyCode == 53, let win = self?.window, win.isVisible {
                self?.cancel()
                self?.onComplete?(.zero)
                return nil
            }
            return ev
        }
    }

    func cancel() {
        if let m = escMonitor {
            NSEvent.removeMonitor(m)
            escMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
    }
}

final class CaptureOverlayView: NSView {
    var onDone: ((CGRect) -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?
    private var selecting = false
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: nil)
        if let ta = trackingArea { addTrackingArea(ta) }
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        selecting = true
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard selecting else { return }
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard selecting, let s = start, let c = current else { return }
        selecting = false
        let rect = NSRect(x: min(s.x, c.x), y: min(s.y, c.y),
                          width: abs(c.x - s.x), height: abs(c.y - s.y))
        needsDisplay = false
        if rect.width > 4 && rect.height > 4 {
            onDone?(rect)
        } else {
            window?.orderOut(nil)
            onDone?(.zero)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc 取消
            window?.orderOut(nil)
            onDone?(.zero)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()
        guard let s = start, let c = current else { return }
        let rect = NSRect(x: min(s.x, c.x), y: min(s.y, c.y),
                          width: abs(c.x - s.x), height: abs(c.y - s.y))
        NSColor.white.withAlphaComponent(0.08).setFill()
        rect.fill()
        NSColor.systemOrange.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()
        let sizeText = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: sizeText, attributes: attrs)
        let size = str.size()
        let textRect = NSRect(x: rect.maxX - size.width - 8, y: rect.maxY + 6,
                              width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: textRect, xRadius: 4, yRadius: 4).fill()
        str.draw(at: NSPoint(x: textRect.minX + 6, y: textRect.minY + 3))
    }
}
