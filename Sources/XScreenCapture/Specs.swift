import AppleViewModel
import XClipEngine

// 宿主模块的统一入口。菜单、设置窗口、录制按钮各自持有 binding，
// 通过相同 key 解析到同一实例；AppDelegate 的 binding 覆盖整个应用生命周期。

@MainActor let statusSpec = ViewModelSpec<StatusViewModel>(key: "status") { StatusViewModel() }

@MainActor let settingsSpec = ViewModelSpec<SettingsViewModel>(key: "settings") {
    SettingsViewModel(defaults: .standard)
}

@MainActor let permissionSpec = ViewModelSpec<PermissionViewModel>(key: "permission") { PermissionViewModel() }

@MainActor let captureSpec = ViewModelSpec<CaptureViewModel>(key: "capture") {
    CaptureViewModel(engine: XCCaptureEngine())
}

@MainActor let shortcutSpec = ViewModelSpec<ShortcutViewModel>(key: "shortcut") {
    ShortcutViewModel(defaults: .standard)
}

@MainActor let updateSpec = ViewModelSpec<UpdateViewModel>(key: "update") {
    UpdateViewModel(defaults: .standard, client: GitHubReleaseClient(), installer: UpdateInstaller())
}
