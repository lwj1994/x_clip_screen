import AppKit
import AppleViewModel
import UniformTypeIdentifiers

/// 菜单栏图标与应用主菜单。快捷键变化时同步菜单等价键和提示。
@MainActor
final class StatusMenuController: NSObject, NSMenuItemValidation, ViewModelBindingRefreshable {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let showSettings: () -> Void
    private var captureItems: [NSMenuItem] = []

    private var capture: CaptureViewModel { viewModelBinding.read(captureSpec) }
    private var shortcut: ShortcutViewModel { viewModelBinding.watch(shortcutSpec) }
    private var permission: PermissionViewModel { viewModelBinding.read(permissionSpec) }
    private var update: UpdateViewModel { viewModelBinding.read(updateSpec) }

    init(showSettings: @escaping () -> Void) {
        self.showSettings = showSettings
        super.init()
        NSApp.mainMenu = makeMainMenu()
        statusItem.menu = makeStatusMenu()
        let icon = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "XScreenCapture 截图")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        render()
    }

    func viewModelBindingDidUpdate() { render() }

    private func render() {
        let state = shortcut.state
        for item in captureItems {
            item.keyEquivalent = state.isAvailable ? state.shortcut.keyEquivalent : ""
            item.keyEquivalentModifierMask = state.shortcut.modifiers
        }
        statusItem.button?.toolTip = "XScreenCapture · \(state.shortcut.displayString) 截图"
    }

    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        captureItems.append(addItem("开始截图", #selector(startCapture(_:)), to: appMenu))
        addItem("设置…", #selector(openSettings(_:)), key: ",", to: appMenu)
        addItem("检查更新…", #selector(checkForUpdates(_:)), to: appMenu)
        addItem("退出 XScreenCapture", #selector(quit(_:)), key: "q", to: appMenu)
        let mainMenu = NSMenu()
        let root = NSMenuItem()
        root.submenu = appMenu
        mainMenu.addItem(root)
        // 截图工具里的文字标注和保存面板需要标准编辑命令。
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"),
                                     ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        let editRoot = NSMenuItem()
        editRoot.submenu = edit
        mainMenu.addItem(editRoot)
        return mainMenu
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        captureItems.append(addItem("开始截图", #selector(startCapture(_:)), to: menu))
        addItem("再次复制上一张", #selector(copyLast(_:)), to: menu)
        addItem("保存上一张…", #selector(saveLast(_:)), to: menu)
        menu.addItem(.separator())
        addItem("设置…", #selector(openSettings(_:)), key: ",", to: menu)
        addItem("屏幕录制权限…", #selector(openPrivacy(_:)), to: menu)
        addItem("检查更新…", #selector(checkForUpdates(_:)), to: menu)
        menu.addItem(.separator())
        addItem("退出 XScreenCapture", #selector(quit(_:)), key: "q", to: menu)
        return menu
    }

    @discardableResult
    private func addItem(_ title: String, _ action: Selector, key: String = "", to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copyLast(_:)), #selector(saveLast(_:)): capture.lastImage != nil
        case #selector(startCapture(_:)): !capture.isBusy
        case #selector(checkForUpdates(_:)): !update.isBusy && !capture.isCapturing
        default: true
        }
    }

    @objc private func startCapture(_ sender: Any?) { capture.start() }
    @objc private func openSettings(_ sender: Any?) { showSettings() }
    @objc private func checkForUpdates(_ sender: Any?) { update.checkForUpdates() }
    @objc private func copyLast(_ sender: Any?) { capture.copyLastImage() }
    @objc private func quit(_ sender: Any?) { NSApp.terminate(nil) }

    @objc private func openPrivacy(_ sender: Any?) {
        let mouse = NSEvent.mouseLocation
        permission.showGuide(from: NSRect(x: mouse.x - 16, y: mouse.y - 16, width: 32, height: 32))
    }

    @objc private func saveLast(_ sender: Any?) {
        guard let image = capture.lastImage else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        panel.nameFieldStringValue = "XScreenCapture \(formatter.string(from: Date())).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try image.write(to: url, options: .atomic)
        } catch {
            viewModelBinding.read(statusSpec).alert(error.localizedDescription)
        }
    }
}
