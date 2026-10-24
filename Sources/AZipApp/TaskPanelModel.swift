import Foundation

/// 独立进度浮窗展示的任务：解压与安装共用同一套外观。
struct TaskPanelState: Identifiable, Sendable {
    enum Kind: Sendable {
        case extracting
        case installing
    }

    let id = UUID()
    let kind: Kind
    let iconURL: URL
    let title: String
    let detail: String
    var progress: Double
    var isFinished: Bool = false
    /// 是否允许取消（安装暂不支持中断）。
    var isCancellable: Bool { kind == .extracting }
}

@MainActor
final class TaskPanelModel: ObservableObject {
    static let shared = TaskPanelModel()

    @Published private(set) var state: TaskPanelState?

    func update(_ state: TaskPanelState?) {
        self.state = state
    }
}
