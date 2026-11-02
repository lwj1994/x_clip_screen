import AppKit
import AppleViewModel

/// 主窗口：开始截图、快捷键、选框颜色、输出与更新设置。
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, ViewModelBindingRefreshable {
    private var settings: SettingsViewModel { viewModelBinding.watch(settingsSpec) }
    private var shortcut: ShortcutViewModel { viewModelBinding.watch(shortcutSpec) }
    private var status: StatusViewModel { viewModelBinding.watch(statusSpec) }
    private var capture: CaptureViewModel { viewModelBinding.watch(captureSpec) }
    private var permission: PermissionViewModel { viewModelBinding.watch(permissionSpec) }
    private var update: UpdateViewModel { viewModelBinding.watch(updateSpec) }

    private let captureButton = NSButton(title: "开始截图", target: nil, action: nil)
    private let permissionLabel = SettingsWindowController.label("", size: 12)
    private let recorder = ShortcutRecorderButton(frame: NSRect(x: 193, y: 249, width: 142, height: 32))
    private let borderColorButton = NSButton(title: "选择颜色", target: nil, action: nil)
    private let borderColorLabel = SettingsWindowController.label("", size: 12)
    private let resolutionBox = NSButton(checkboxWithTitle: "保存时保留 Retina 分辨率", target: nil, action: nil)
    private let soundBox = NSButton(checkboxWithTitle: "截图提示音", target: nil, action: nil)
    private let autoUpdateBox = NSButton(checkboxWithTitle: "自动检查更新", target: nil, action: nil)
    private let checkUpdateButton = NSButton(title: "检查更新", target: nil, action: nil)
    private let resultLabel = SettingsWindowController.label("", size: 11)
    private var renderScheduled = false

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "XScreenCapture"
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.titlebarAppearsTransparent = true
        super.init(window: window)
        window.delegate = self
        buildContent(in: window.contentView!)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        render()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func cancelShortcutRecording() { recorder.cancelRecording() }

    func viewModelBindingDidUpdate() {
        // 截图在下一轮主线程启动；隐藏窗口必须在此之前同步完成。
        if capture.state.isPending {
            NSColorPanel.shared.orderOut(nil)
            window?.orderOut(nil)
        }
        // 同一轮内的多次通知合并为一次渲染。
        guard !renderScheduled else { return }
        renderScheduled = true
        Task { @MainActor [weak self] in
            self?.renderScheduled = false
            self?.render()
        }
    }

    private func render() {
        let settings = settings.state
        captureButton.title = "开始截图   \(shortcut.shortcut.displayString)"
        let granted = permission.isGranted
        permissionLabel.stringValue = granted ? "截图已就绪" : "首次截图需要允许屏幕录制权限"
        permissionLabel.textColor = granted ? .secondaryLabelColor : .systemOrange
        let color = self.settings.borderColor
        borderColorButton.image = NSImage(size: NSSize(width: 26, height: 14), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            return true
        }
        borderColorLabel.stringValue = settings.borderColorHex
        resolutionBox.state = settings.highResolution ? .on : .off
        soundBox.state = settings.playSound ? .on : .off
        autoUpdateBox.state = settings.automaticUpdateCheck ? .on : .off
        checkUpdateButton.isEnabled = !update.isBusy
        resultLabel.stringValue = status.state.message
    }

    private func buildContent(in content: NSView) {
        let symbol = NSImageView(frame: NSRect(x: 201, y: 486, width: 78, height: 78))
        symbol.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "截图")
        symbol.contentTintColor = .systemTeal
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 58, weight: .light)
        content.addSubview(symbol)
        place(Self.label("XScreenCapture", size: 34, weight: .semibold), NSRect(x: 40, y: 435, width: 400, height: 48), in: content)
        let subtitle = Self.label("框选、标注，然后分享。", size: 16)
        subtitle.textColor = .secondaryLabelColor
        place(subtitle, NSRect(x: 30, y: 402, width: 420, height: 26), in: content)

        configure(captureButton, #selector(startCapture(_:)))
        captureButton.controlSize = .large
        captureButton.bezelColor = .systemTeal
        captureButton.keyEquivalent = "\r"
        place(captureButton, NSRect(x: 85, y: 340, width: 310, height: 44), in: content)
        place(permissionLabel, NSRect(x: 20, y: 308, width: 440, height: 24), in: content)

        place(Self.label("截图快捷键", size: 13, weight: .medium, alignment: .left), NSRect(x: 65, y: 254, width: 120, height: 24), in: content)
        content.addSubview(recorder)
        let resetShortcut = NSButton(title: "恢复默认", target: self, action: #selector(resetShortcut(_:)))
        configure(resetShortcut, #selector(resetShortcut(_:)))
        place(resetShortcut, NSRect(x: 341, y: 249, width: 83, height: 32), in: content)

        place(Self.label("选框边框颜色", size: 13, weight: .medium, alignment: .left), NSRect(x: 65, y: 208, width: 120, height: 24), in: content)
        configure(borderColorButton, #selector(chooseBorderColor(_:)))
        borderColorButton.imagePosition = .imageOnly
        borderColorButton.setAccessibilityLabel("选框边框颜色")
        place(borderColorButton, NSRect(x: 194, y: 203, width: 46, height: 32), in: content)
        borderColorLabel.alignment = .left
        borderColorLabel.textColor = .secondaryLabelColor
        place(borderColorLabel, NSRect(x: 251, y: 208, width: 92, height: 24), in: content)
        let resetColor = NSButton(title: "恢复默认", target: nil, action: nil)
        configure(resetColor, #selector(resetBorderColor(_:)))
        place(resetColor, NSRect(x: 341, y: 203, width: 83, height: 32), in: content)
        NSColorPanel.shared.showsAlpha = false

        resolutionBox.target = self; resolutionBox.action = #selector(toggleResolution(_:))
        place(resolutionBox, NSRect(x: 65, y: 143, width: 230, height: 24), in: content)
        soundBox.target = self; soundBox.action = #selector(toggleSound(_:))
        place(soundBox, NSRect(x: 299, y: 143, width: 120, height: 24), in: content)
        autoUpdateBox.target = self; autoUpdateBox.action = #selector(toggleAutomaticUpdate(_:))
        place(autoUpdateBox, NSRect(x: 65, y: 115, width: 220, height: 24), in: content)
        configure(checkUpdateButton, #selector(checkForUpdates(_:)))
        checkUpdateButton.toolTip = "当前版本 \(AppVersion.current)"
        place(checkUpdateButton, NSRect(x: 293, y: 111, width: 131, height: 32), in: content)

        let tip = Self.label("悬停选窗 · 拖动框选 · 双击完成 · Esc 取消", size: 12)
        tip.textColor = .secondaryLabelColor
        place(tip, NSRect(x: 20, y: 78, width: 440, height: 24), in: content)
        resultLabel.textColor = .tertiaryLabelColor
        resultLabel.maximumNumberOfLines = 2
        place(resultLabel, NSRect(x: 20, y: 36, width: 440, height: 32), in: content)
    }

    private func configure(_ button: NSButton, _ action: Selector) {
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
    }

    private func place(_ view: NSView, _ frame: NSRect, in content: NSView) {
        view.frame = frame
        content.addSubview(view)
    }

    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                              alignment: NSTextAlignment = .center) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.alignment = alignment
        return label
    }

    @objc private func startCapture(_ sender: NSButton) {
        guard !recorder.isRecording else { return }
        let source = sender.window?.convertToScreen(sender.convert(sender.bounds, to: nil))
        capture.start(from: source)
    }

    @objc private func resetShortcut(_ sender: Any?) {
        recorder.cancelRecording()
        shortcut.restoreDefault()
    }

    @objc private func chooseBorderColor(_ sender: Any?) {
        recorder.cancelRecording()
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSColorPanel.shared
        panel.color = settings.borderColor
        panel.setTarget(self)
        panel.setAction(#selector(changeBorderColor(_:)))
        panel.isContinuous = true
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func changeBorderColor(_ sender: NSColorPanel) { settings.setBorderColor(sender.color) }
    @objc private func resetBorderColor(_ sender: Any?) { settings.resetBorderColor() }
    @objc private func toggleResolution(_ sender: NSButton) { settings.setHighResolution(sender.state == .on) }
    @objc private func toggleSound(_ sender: NSButton) { settings.setPlaySound(sender.state == .on) }
    @objc private func toggleAutomaticUpdate(_ sender: NSButton) { settings.setAutomaticUpdateCheck(sender.state == .on) }
    @objc private func checkForUpdates(_ sender: Any?) { update.checkForUpdates() }
}
