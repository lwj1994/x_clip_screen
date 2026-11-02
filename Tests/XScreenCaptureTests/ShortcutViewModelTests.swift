import AppKit
import AppleViewModel
import Carbon.HIToolbox
import XCTest
@testable import XScreenCapture

// 真实 Carbon 注册测试：使用独立偏好 suite，不创建窗口、不合成按键，结束时释放全部注册。
final class ShortcutViewModelTests: XCTestCase {
    private let flags: NSEvent.ModifierFlags = [.control, .option, .command]
    private let carbonFlags = UInt32(controlKey | optionKey | cmdKey)
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { ViewModel.reset() }
        suiteName = "milu.qqjietu.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        MainActor.assumeIsolated { ViewModel.reset() }
        super.tearDown()
    }

    @MainActor
    private func makeSpec() -> ViewModelSpec<ShortcutViewModel> {
        let defaults = defaults!
        return ViewModelSpec<ShortcutViewModel>(key: "shortcut-test") { ShortcutViewModel(defaults: defaults) }
    }

    private func probe(_ keyCode: Int, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), carbonFlags, EventHotKeyID(signature: 0x5853_5474, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        return status == noErr ? ref : nil
    }

    @MainActor
    func testRegistrationIsTransactionalPersistedAndReleased() throws {
        let spec = makeSpec()
        let binding = ViewModelBinding()
        var vm: ShortcutViewModel { binding.read(spec) }

        XCTAssertEqual(vm.shortcut, .default, "无偏好时默认为 ⌘⇧2")

        try vm.update(Shortcut(keyCode: UInt16(kVK_F18), modifiers: flags))
        XCTAssertTrue(vm.state.isAvailable)
        XCTAssertEqual(vm.shortcut.displayString, "⌃⌥⌘F18")
        XCTAssertEqual(vm.shortcut.keyEquivalent.utf16.first, UInt16(NSF18FunctionKey))
        XCTAssertEqual(defaults.integer(forKey: DefaultsKey.shortcutKeyCode), kVK_F18)
        XCTAssertEqual(UInt(defaults.integer(forKey: DefaultsKey.shortcutModifiers)), flags.rawValue)
        let saved = defaults.persistentDomain(forName: suiteName) as NSDictionary?

        let blocker = try XCTUnwrap(probe(kVK_F19, id: 1), "建立 ⌃⌥⌘F19 冲突注册")
        defer { UnregisterEventHotKey(blocker) }
        XCTAssertThrowsError(try vm.update(Shortcut(keyCode: UInt16(kVK_F19), modifiers: flags)))
        XCTAssertTrue(vm.state.isAvailable, "冲突失败后旧快捷键仍可用")
        XCTAssertEqual(vm.shortcut.keyCode, UInt16(kVK_F18))
        XCTAssertEqual(defaults.persistentDomain(forName: suiteName) as NSDictionary?, saved, "冲突失败不改变持久化设置")

        XCTAssertThrowsError(try vm.update(Shortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: .shift))) {
            XCTAssertEqual($0 as? ShortcutError, .invalid)
        }
        XCTAssertThrowsError(try vm.update(Shortcut(keyCode: UInt16(kVK_Escape), modifiers: flags)), "Esc 保留为取消键")
        XCTAssertEqual(vm.shortcut.keyCode, UInt16(kVK_F18))
        XCTAssertEqual(defaults.persistentDomain(forName: suiteName) as NSDictionary?, saved)

        try vm.update(Shortcut(keyCode: UInt16(kVK_F20), modifiers: flags))
        XCTAssertEqual(vm.shortcut.keyCode, UInt16(kVK_F20))
        let releasedF18 = try XCTUnwrap(probe(kVK_F18, id: 2), "成功替换后旧 F18 注册已释放")
        UnregisterEventHotKey(releasedF18)

        binding.dispose()
        let releasedF20 = try XCTUnwrap(probe(kVK_F20, id: 3), "binding 释放后 ViewModel 撤销注册")
        UnregisterEventHotKey(releasedF20)

        let restoredBinding = ViewModelBinding()
        defer { restoredBinding.dispose() }
        let restored = restoredBinding.read(spec)
        XCTAssertEqual(restored.shortcut, Shortcut(keyCode: UInt16(kVK_F20), modifiers: flags), "重建时读取保存的组合")
        try restored.register()
        XCTAssertTrue(restored.state.isAvailable)
    }

    @MainActor
    func testRecordingPausesRegistrationAndRestoresOnCancelOrInvalidInput() throws {
        let spec = makeSpec()
        let binding = ViewModelBinding()
        defer { binding.dispose() }
        var vm: ShortcutViewModel { binding.read(spec) }
        try vm.update(Shortcut(keyCode: UInt16(kVK_F18), modifiers: flags))

        vm.beginRecording()
        XCTAssertFalse(vm.state.isAvailable)
        let paused = try XCTUnwrap(probe(kVK_F18, id: 4), "录制期间暂停注册")
        UnregisterEventHotKey(paused)

        vm.cancelRecording()
        XCTAssertTrue(vm.state.isAvailable)
        XCTAssertEqual(vm.shortcut.keyCode, UInt16(kVK_F18))

        vm.beginRecording()
        vm.finishRecording(Shortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: .shift))
        XCTAssertTrue(vm.state.isAvailable, "无效组合保留原注册")
        XCTAssertEqual(vm.shortcut.keyCode, UInt16(kVK_F18))
        XCTAssertEqual(binding.read(statusSpec).state.message, ShortcutError.invalid.errorDescription)

        vm.beginRecording()
        vm.finishRecording(Shortcut(keyCode: UInt16(kVK_F20), modifiers: flags))
        XCTAssertEqual(vm.shortcut.keyCode, UInt16(kVK_F20))
        XCTAssertEqual(binding.read(statusSpec).state.message, "截图快捷键已设为 ⌃⌥⌘F20。")
    }
}
