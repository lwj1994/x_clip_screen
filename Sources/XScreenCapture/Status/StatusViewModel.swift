import AppleViewModel
import Foundation

struct StatusState: Equatable {
    /// 设置窗口底部的最近一条提示。
    var message: String
    /// 需要用户确认的错误；由 AppDelegate 弹窗后清除。
    var alert: String?
}

/// 各模块共享的提示通道，避免模块之间直接引用 UI。
@MainActor
final class StatusViewModel: StateViewModel<StatusState> {
    static let idleMessage = "关闭此窗口后，仍可从菜单栏或快捷键截图。"

    init() {
        super.init(state: StatusState(message: Self.idleMessage, alert: nil), equals: { $0 == $1 })
    }

    func post(_ message: String) {
        var next = state
        next.message = message
        setState(next)
    }

    func alert(_ message: String) {
        var next = state
        next.alert = message
        setState(next)
    }

    func dismissAlert() {
        guard state.alert != nil else { return }
        var next = state
        next.alert = nil
        setState(next)
    }
}
