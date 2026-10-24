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
    /// 解压与安装都支持取消。
    var isCancellable: Bool { true }
}

@MainActor
final class TaskPanelModel: ObservableObject {
    static let shared = TaskPanelModel()

    @Published private(set) var state: TaskPanelState?

    func update(_ state: TaskPanelState?) {
        self.state = state
    }
}
