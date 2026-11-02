import AppKit
import AppleViewModel
import Carbon.HIToolbox

/// 点击后录制一次组合。Esc、点击其他位置、窗口或应用失焦都会取消。
@MainActor
final class ShortcutRecorderButton: NSButton, ViewModelBindingRefreshable {
    private var shortcut: ShortcutViewModel { viewModelBinding.watch(shortcutSpec) }
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    var isRecording: Bool { eventMonitor != nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording(_:))
        toolTip = "点击后按下新组合；Esc 或点击其他位置取消。"
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow != window { cancelRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    func viewModelBindingDidUpdate() { render() }

    func cancelRecording() {
        guard isRecording else { return }
        stopMonitoring()
        shortcut.cancelRecording()
    }

    private func render() {
        title = shortcut.state.isRecording ? "请按快捷键…" : shortcut.shortcut.displayString
    }

    @objc private func toggleRecording(_ sender: Any?) {
        if isRecording { cancelRecording(); return }
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard window.makeFirstResponder(self) else { return }
        let cancel: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelRecording() }
        }
        observers = [
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                                   queue: .main, using: cancel),
            NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp,
                                                   queue: .main, using: cancel)
        ]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.consumes(event) ?? false }
            return consumed ? nil : event
        }
        shortcut.beginRecording()
    }

    /// 返回 true 时吞掉该事件。
    private func consumes(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        if event.type == .keyDown {
            if event.keyCode == UInt16(kVK_Escape) {
                cancelRecording()
            } else if !event.isARepeat {
                stopMonitoring()
                shortcut.finishRecording(Shortcut(keyCode: event.keyCode, modifiers: event.modifierFlags))
            }
            return true
        }
        let clickedRecorder = event.window == window && bounds.contains(convert(event.locationInWindow, from: nil))
        cancelRecording()
        return clickedRecorder
    }

    private func stopMonitoring() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}
