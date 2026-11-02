import AppKit
import Carbon.HIToolbox

/// 物理键码加 AppKit 修饰位；不使用 Carbon 位值保存。
struct Shortcut: Equatable, Sendable {
    static let allowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    static let `default` = Shortcut(keyCode: UInt16(kVK_ANSI_2), modifiers: [.command, .shift])

    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.allowedModifiers)
    }

    /// 必须含 ⌘、⌃ 或 ⌥；Esc 保留为取消键，单独的修饰键无效。
    var isValid: Bool {
        guard !modifiers.isDisjoint(with: [.command, .control, .option]), keyCode < 128 else { return false }
        let reserved = [kVK_Escape, kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option,
                        kVK_RightOption, kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function]
        return !reserved.contains(Int(keyCode))
    }

    var carbonModifiers: UInt32 {
        var result = 0
        if modifiers.contains(.command) { result |= cmdKey }
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.command) { text += "⌘" }
        if modifiers.contains(.shift) { text += "⇧" }
        return text + Self.keyDisplay(keyCode)
    }

    /// 菜单等价键字符；随当前键盘布局翻译。
    var keyEquivalent: String { Self.keyCharacter(keyCode) }

    private static let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                       kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    private static func character(_ value: Int) -> String { String(UnicodeScalar(UInt16(value)).map(Character.init) ?? " ") }

    private static func keyCharacter(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Return: return "\r"
        case kVK_Tab: return "\t"
        case kVK_Space: return " "
        case kVK_Delete: return "\u{8}"
        case kVK_ANSI_KeypadEnter: return character(NSEnterCharacter)
        case kVK_ForwardDelete: return character(NSDeleteFunctionKey)
        case kVK_LeftArrow: return character(NSLeftArrowFunctionKey)
        case kVK_RightArrow: return character(NSRightArrowFunctionKey)
        case kVK_UpArrow: return character(NSUpArrowFunctionKey)
        case kVK_DownArrow: return character(NSDownArrowFunctionKey)
        case kVK_Home: return character(NSHomeFunctionKey)
        case kVK_End: return character(NSEndFunctionKey)
        case kVK_PageUp: return character(NSPageUpFunctionKey)
        case kVK_PageDown: return character(NSPageDownFunctionKey)
        case kVK_ANSI_KeypadClear: return character(NSClearLineFunctionKey)
        default: break
        }
        if let index = functionKeys.firstIndex(of: Int(keyCode)) { return character(NSF1FunctionKey + index) }
        return translate(keyCode)
    }

    private static func translate(_ keyCode: UInt16) -> String {
        var source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        var layoutData = source.flatMap { TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) }
        if layoutData == nil {
            source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
            layoutData = source.flatMap { TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) }
        }
        guard let layoutData else { return "" }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return "" }
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 8)
        var length = 0
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return "" }
        return String(utf16CodeUnits: characters, count: length).lowercased()
    }

    private static func keyDisplay(_ keyCode: UInt16) -> String {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "空格", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_ANSI_KeypadEnter: "⌤", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
            kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_ANSI_KeypadClear: "清除"
        ]
        if let label = special[Int(keyCode)] { return label }
        if let index = functionKeys.firstIndex(of: Int(keyCode)) { return "F\(index + 1)" }
        let character = translate(keyCode)
        return character.isEmpty ? "键 \(keyCode)" : character.uppercased()
    }
}
