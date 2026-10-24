import Foundation
import SwiftUI
import AZipCore

/// 一次解压任务的可观察状态。
struct ExtractionJob: Identifiable, Sendable {
    enum Phase: Sendable {
        case running
        case finished(URL)
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let sourceURL: URL
    let destination: URL
    var progress: Double = 0
    var phase: Phase = .running
    let startedAt = Date()
}

/// 解压进度回调运行在非隔离上下文，取消标志需要自己保证线程安全。
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        value = false
        lock.unlock()
    }
}

@MainActor
final class ArchiveSession: ObservableObject {
    static let shared = ArchiveSession()

    @Published private(set) var job: ExtractionJob?

    private let cancelFlag = CancelFlag()

    /// 支持自动解压的扩展名（与 Core 的解压器保持一致）。
    static var supportedExtensions: Set<String> { ArchiveExtractor.supportedExtensions }

    func extract(url: URL) {
        guard job == nil else { return }

        let destination = ArchiveExtractor.defaultDestination(for: url)
        cancelFlag.reset()
        job = ExtractionJob(sourceURL: url, destination: destination)

        // 独立浮窗承载进度，主窗口先让位。
        let mainWindow = NSApp.windows.first {
            $0.identifier?.rawValue == "AZipMainWindow"
        }
        ExtractionWindowController.shared.show(over: mainWindow)

        Task {
            do {
                try await ArchiveExtractor.extract(
                    archiveURL: url,
                    to: destination,
                    progress: { value in
                        Task { @MainActor in
                            guard var current = self.job else { return }
                            current.progress = value
                            self.job = current
                        }
                    },
                    isCancelled: { [cancelFlag] in
                        cancelFlag.isSet
                    }
                )
                guard var current = job else { return }
                current.progress = 1
                current.phase = .finished(destination)
                job = current
                scheduleTermination(after: 1.2) { if case .finished = $0 { return true }; return false }

                // 用户显式勾选「解压后删除压缩包」时才动原文件，
                // 且只移到废纸篓（可恢复），不做不可逆删除。
                if UserDefaults.standard.bool(forKey: "deleteArchiveAfterExtraction") {
                    var trashed: NSURL?
                    try? FileManager.default.trashItem(
                        at: url,
                        resultingItemURL: &trashed
                    )
                }
            } catch {
                guard var current = job else { return }
                if case ArchiveError.cancelled = error {
                    current.phase = .cancelled
                    scheduleTermination(after: 0.6) { if case .cancelled = $0 { return true }; return false }
                } else {
                    current.phase = .failed(error.localizedDescription)
                }
                job = current
            }
        }
    }

    func cancel() {
        cancelFlag.set()
    }

    /// 完成/取消后自动关闭浮窗；失败保留，让用户看到原因。
    /// 解压结束（成功或取消）后关闭浮窗并退出应用——AZip 此时只是解压工具。
    private func scheduleTermination(
        after seconds: Double,
        matches: @escaping (ExtractionJob.Phase) -> Bool
    ) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard let current = job, matches(current.phase) else { return }
            _ = current
            job = nil
            ExtractionWindowController.shared.close()
            NSApp.terminate(nil)
        }
    }

    func dismiss() {
        guard let job else { return }
        if case .running = job.phase {
            cancelFlag.set()
            return
        }
        self.job = nil
        ExtractionWindowController.shared.close()
        exitIfNoVisibleMainWindow()
    }

    private func exitIfNoVisibleMainWindow() {
        let hasVisibleMain = NSApp.windows.contains {
            $0.identifier?.rawValue == "AZipMainWindow" && $0.isVisible
        }
        if !hasVisibleMain {
            NSApp.terminate(nil)
        }
    }

    func revealInFinder() {
        guard case let .finished(url) = job?.phase else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        job = nil
    }
}
