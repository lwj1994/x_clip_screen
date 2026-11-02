import AppKit
import Carbon.HIToolbox

/// 一个全局 Carbon 热键。替换是事务式的：新组合注册成功后才撤销旧注册。
@MainActor
final class HotKeyRegistration {
    private static let signature: OSType = 0x5853_4370 // 'XSCp'

    var onPressed: (@MainActor () -> Void)?

    // deinit 非隔离，需直接释放 Carbon 资源。
    nonisolated(unsafe) private var hotKey: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    private var identifier: UInt32 = 0

    var isRegistered: Bool { hotKey != nil }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func register(_ shortcut: Shortcut) throws {
        try installEventHandler()
        var replacement: EventHotKeyRef?
        let next = identifier + 1
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                         EventHotKeyID(signature: Self.signature, id: next),
                                         GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr, let replacement else {
            throw ShortcutError.occupied(status)
        }
        let previous = hotKey
        hotKey = replacement
        identifier = next
        if let previous { UnregisterEventHotKey(previous) }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installEventHandler() throws {
        guard eventHandler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // 事件处理器在 deinit 中移除，生命周期内用非持有指针即可。
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let registration = Unmanaged<HotKeyRegistration>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated { registration.handle(event) } ? noErr : OSStatus(eventNotHandledErr)
        }, 1, &type, context, &eventHandler)
        guard status == noErr else { throw ShortcutError.handlerUnavailable(status) }
    }

    private func handle(_ event: EventRef) -> Bool {
        var pressed = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                       nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
        guard status == noErr, pressed.signature == Self.signature, pressed.id == identifier, hotKey != nil else { return false }
        onPressed?()
        return true
    }
}

enum ShortcutError: LocalizedError, Equatable {
    case invalid
    case recording
    case occupied(OSStatus)
    case handlerUnavailable(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalid: "请同时按住 ⌘、⌃ 或 ⌥ 中至少一个修饰键，再按一个按键。"
        case .recording: "请先结束快捷键录制。"
        case .occupied: "该组合可能已被系统或其他应用占用，未更改原快捷键。"
        case .handlerUnavailable: "无法安装快捷键监听，请重新打开应用。"
        }
    }
}
