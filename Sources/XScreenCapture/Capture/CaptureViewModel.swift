import AppKit
import AppleViewModel
import XClipEngine

struct CaptureState: Equatable {
    /// 已请求截图、等待下一轮主线程启动引擎；设置窗口据此先隐藏自身。
    var isPending = false
    var hasLastImage = false
}

/// 截图会话：加载引擎、启动截图并处理完成回调。
@MainActor
final class CaptureViewModel: StateViewModel<CaptureState> {
    private let engine: XCCaptureEngine
    private var delegate: CaptureRequestDelegate?
    private(set) var lastImage: Data?

    private var status: StatusViewModel { viewModelBinding.read(statusSpec) }
    private var permission: PermissionViewModel { viewModelBinding.read(permissionSpec) }

    init(engine: XCCaptureEngine) {
        self.engine = engine
        super.init(state: CaptureState(), equals: { $0 == $1 })
        addDispose { [weak self] in self?.engine.cancel() }
    }

    /// 引擎截图浮层是否在显示；由原框架维护，不进入 state。
    var isCapturing: Bool { engine.capturing }
    var isBusy: Bool { state.isPending || engine.capturing }

    func load() throws { try engine.load() }

    func cancel() { engine.cancel() }

    /// source 为未授权时权限引导动画的起点，缺省使用鼠标位置。
    func start(from source: NSRect? = nil) {
        guard !isBusy else { return }
        guard permission.isGranted else {
            let mouse = NSEvent.mouseLocation
            permission.showGuide(from: source ?? NSRect(x: mouse.x - 16, y: mouse.y - 16, width: 32, height: 32))
            return
        }
        setPending(true)
        // 下一轮主线程再启动，让菜单退出跟踪；不做固定延迟或窗口过渡动画。
        taskScope.task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            self.setPending(false)
            NSApp.activate(ignoringOtherApps: true)
            let delegate = CaptureRequestDelegate(owner: self)
            self.delegate = delegate
            do {
                try self.engine.start(withDelegate: delegate)
                if ProcessInfo.processInfo.environment["XCLIP_TRACE"] != nil {
                    NSLog("XScreenCapture capture started windows=%lu", NSApp.windows.count)
                }
            } catch {
                self.status.alert(error.localizedDescription)
            }
        }
    }

    func copyLastImage() {
        guard let lastImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(lastImage, forType: .png)
    }

    fileprivate func didCancel() {
        if ProcessInfo.processInfo.environment["XCLIP_TRACE"] != nil {
            NSLog("XScreenCapture capture cancelled: %@", Thread.callStackSymbols)
        }
        status.post("已取消截图。")
    }

    fileprivate func didChange() { engine.cancel() }

    // 引擎已负责写入剪贴板及保存文件，这里只核对结果。
    fileprivate func didFinish(data: Data?, path: String?, error: Error?) {
        if let error {
            status.alert(error.localizedDescription)
            return
        }
        guard let data, !data.isEmpty, NSBitmapImageRep(data: data) != nil else {
            status.alert("没有收到有效截图，请检查屏幕录制权限后重试。")
            return
        }
        lastImage = data
        var next = state
        next.hasLastImage = true
        setState(next)
        if let path, !path.isEmpty {
            // 原框架保存失败也可能返回 error=nil，必须核对磁盘结果。
            guard let saved = FileManager.default.contents(atPath: path), NSBitmapImageRep(data: saved) != nil else {
                status.alert("无法确认图片已保存。请从菜单栏选择“保存上一张…”重试。")
                return
            }
            status.post("已保存：" + (path as NSString).lastPathComponent)
        } else {
            status.post("已复制到剪贴板，可直接粘贴。")
        }
    }

    private func setPending(_ pending: Bool) {
        var next = state
        next.isPending = pending
        setState(next)
    }
}

/// 原框架通过 Objective-C 选择器回调 delegate；签名来自 QQ 自身调用点。
@MainActor
private final class CaptureRequestDelegate: NSObject {
    private weak var owner: CaptureViewModel?

    init(owner: CaptureViewModel) { self.owner = owner }

    @objc(captureRequestDidCancel:)
    func captureRequestDidCancel(_ request: Any?) { owner?.didCancel() }

    @objc(captureRequestDidChange:)
    func captureRequestDidChange(_ request: Any?) { owner?.didChange() }

    @objc(captureRequest:didFinishWithImageData:saveToPath:error:)
    func captureRequest(_ request: Any?, didFinishWithImageData data: Data?, saveToPath path: String?, error: Error?) {
        owner?.didFinish(data: data, path: path, error: error)
    }
}
