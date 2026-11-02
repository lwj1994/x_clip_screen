import AppKit
import AppleViewModel
import XClipEngine

/// 偏好键与引擎共用：截图引擎直接读取分辨率、提示音和选框颜色。
enum DefaultsKey {
    static let highResolution = "XCHighResolution"
    static let playSound = "XCPlaySound"
    static let borderColor = XCSelectionBorderColorDefaultsKey
    static let automaticUpdateCheck = "XCAutomaticUpdateCheck"
    static let lastUpdateCheck = "XCLastUpdateCheck"
    static let shortcutKeyCode = "XCShortcutKeyCode"
    static let shortcutModifiers = "XCShortcutModifiers"
}

/// 选框颜色以 sRGB `#RRGGBB` 保存。
enum SelectionColor {
    static let defaultHex = "#0099FF"

    static func hex(from color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }

    static func color(fromHex hex: String) -> NSColor {
        var value: UInt64 = 0x0099FF
        if hex.hasPrefix("#"), hex.count == 7, let parsed = UInt64(hex.dropFirst(), radix: 16) { value = parsed }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

struct SettingsState: Equatable {
    var highResolution: Bool
    var playSound: Bool
    var borderColorHex: String
    var automaticUpdateCheck: Bool
}

@MainActor
final class SettingsViewModel: StateViewModel<SettingsState> {
    private let defaults: UserDefaults
    private var status: StatusViewModel { viewModelBinding.read(statusSpec) }

    init(defaults: UserDefaults) {
        defaults.register(defaults: [
            DefaultsKey.highResolution: true,
            DefaultsKey.playSound: false,
            DefaultsKey.borderColor: SelectionColor.defaultHex,
            DefaultsKey.automaticUpdateCheck: true
        ])
        self.defaults = defaults
        super.init(state: SettingsState(
            highResolution: defaults.bool(forKey: DefaultsKey.highResolution),
            playSound: defaults.bool(forKey: DefaultsKey.playSound),
            borderColorHex: defaults.string(forKey: DefaultsKey.borderColor) ?? SelectionColor.defaultHex,
            automaticUpdateCheck: defaults.bool(forKey: DefaultsKey.automaticUpdateCheck)
        ), equals: { $0 == $1 })
    }

    var borderColor: NSColor { SelectionColor.color(fromHex: state.borderColorHex) }

    func setHighResolution(_ enabled: Bool) {
        defaults.set(enabled, forKey: DefaultsKey.highResolution)
        mutate { $0.highResolution = enabled }
    }

    func setPlaySound(_ enabled: Bool) {
        defaults.set(enabled, forKey: DefaultsKey.playSound)
        mutate { $0.playSound = enabled }
    }

    func setAutomaticUpdateCheck(_ enabled: Bool) {
        defaults.set(enabled, forKey: DefaultsKey.automaticUpdateCheck)
        mutate { $0.automaticUpdateCheck = enabled }
    }

    func setBorderColor(_ color: NSColor) {
        guard let hex = SelectionColor.hex(from: color) else { return }
        storeBorderColor(hex)
        status.post("选框颜色已保存，下次截图生效。")
    }

    func resetBorderColor() {
        storeBorderColor(SelectionColor.defaultHex)
        status.post("已恢复默认选框颜色。")
    }

    private func storeBorderColor(_ hex: String) {
        defaults.set(hex, forKey: DefaultsKey.borderColor)
        mutate { $0.borderColorHex = hex }
        XCRefreshSelectionBorderColor()
    }

    private func mutate(_ change: (inout SettingsState) -> Void) {
        var next = state
        change(&next)
        setState(next)
    }
}
