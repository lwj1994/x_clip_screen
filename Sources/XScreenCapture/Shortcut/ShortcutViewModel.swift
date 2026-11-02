import AppKit
import AppleViewModel

struct ShortcutState: Equatable {
    var shortcut: Shortcut
    var isRegistered: Bool
    var isRecording: Bool

    /// 录制期间暂停注册，此时快捷键不可用。
    var isAvailable: Bool { isRegistered && !isRecording }
}

/// 截图全局快捷键：持久化、注册与录制流程。所有方法在主线程调用。
@MainActor
final class ShortcutViewModel: StateViewModel<ShortcutState> {
    private let defaults: UserDefaults
    private let hotKey = HotKeyRegistration()

    private var capture: CaptureViewModel { viewModelBinding.read(captureSpec) }
    private var status: StatusViewModel { viewModelBinding.read(statusSpec) }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let stored = Shortcut(keyCode: UInt16(clamping: defaults.integer(forKey: DefaultsKey.shortcutKeyCode)),
                              modifiers: NSEvent.ModifierFlags(rawValue: UInt(clamping: defaults.integer(forKey: DefaultsKey.shortcutModifiers))))
        let hasStored = defaults.object(forKey: DefaultsKey.shortcutKeyCode) != nil
        super.init(state: ShortcutState(shortcut: hasStored && stored.isValid ? stored : .default,
                                        isRegistered: false, isRecording: false),
                   equals: { $0 == $1 })
        hotKey.onPressed = { [weak self] in self?.capture.start() }
        addDispose { [hotKey] in hotKey.unregister() }
    }

    var shortcut: Shortcut { state.shortcut }

    /// 按当前组合注册；录制结束或取消时也用它恢复。
    func register() throws {
        try apply(state.shortcut)
    }

    /// 新组合注册成功后才撤销旧注册并写入偏好；失败时原组合保持不变。
    func update(_ shortcut: Shortcut) throws {
        guard shortcut.isValid else { throw ShortcutError.invalid }
        guard !state.isRecording else { throw ShortcutError.recording }
        try apply(shortcut)
    }

    func restoreDefault() {
        do {
            try update(.default)
            status.post("已恢复默认快捷键。")
        } catch {
            status.post(error.localizedDescription)
        }
    }

    func beginRecording() {
        guard !state.isRecording else { return }
        hotKey.unregister()
        mutate { $0.isRecording = true; $0.isRegistered = false }
        status.post("按下新组合（需含 ⌘、⌃ 或 ⌥）；Esc 取消。")
    }

    func finishRecording(_ shortcut: Shortcut) {
        guard state.isRecording else { return }
        mutate { $0.isRecording = false }
        // 先恢复旧注册，再走事务式替换，失败时旧组合继续生效。
        let restored = (try? register()) != nil
        do {
            try update(shortcut)
            status.post("截图快捷键已设为 \(self.shortcut.displayString)。")
        } catch {
            var message = error.localizedDescription
            if !restored { message += " 原组合也暂时无法注册，请从菜单栏截图。" }
            status.post(message)
        }
    }

    func cancelRecording() {
        guard state.isRecording else { return }
        mutate { $0.isRecording = false }
        let restored = (try? register()) != nil
        status.post(restored ? "已取消快捷键录制。" : "已取消录制，但原快捷键暂时无法注册，请从菜单栏截图。")
    }

    private func apply(_ shortcut: Shortcut) throws {
        if hotKey.isRegistered, shortcut == state.shortcut { return }
        do {
            try hotKey.register(shortcut)
        } catch {
            mutate { $0.isRegistered = self.hotKey.isRegistered }
            throw error
        }
        defaults.set(Int(shortcut.keyCode), forKey: DefaultsKey.shortcutKeyCode)
        defaults.set(Int(shortcut.modifiers.rawValue), forKey: DefaultsKey.shortcutModifiers)
        mutate { $0.shortcut = shortcut; $0.isRegistered = true }
    }

    private func mutate(_ change: (inout ShortcutState) -> Void) {
        var next = state
        change(&next)
        setState(next)
    }
}
