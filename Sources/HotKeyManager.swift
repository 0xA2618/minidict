import Carbon

final class HotKeyManager {
    static let shared = HotKeyManager()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var installed = false

    private init() {}

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, handler: @escaping () -> Void) {
        if !installed {
            installHandler()
            installed = true
        }
        var hotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID(signature: OSType(0x4D4E4454), id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            refs.append(hotKeyRef)
            handlers[id] = handler
        } else {
            NSLog("[MiniDict] 热键注册失败 id=\(id) status=\(status)")
        }
    }

    func unregisterAll() {
        for ref in refs {
            if let r = ref {
                UnregisterEventHotKey(r)
            }
        }
        refs.removeAll()
        handlers.removeAll()
    }

    func dispatch(id: UInt32) {
        handlers[id]?()
    }

    private func installHandler() {
        let handler: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID)
            if status == noErr {
                HotKeyManager.shared.dispatch(id: hotKeyID.id)
            }
            return noErr
        }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
    }
}
