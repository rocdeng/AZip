import AppKit
import OSLog
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

        updatePanel(
            url: url,
            progress: 0,
            detail: NSLocalizedString("准备中…", comment: ""),
            finished: false,
            indeterminate: true
        )
        startElapsedTimer(url: url)

        // 独立浮窗承载进度，主窗口先让位。
        let mainWindow = NSApp.windows.first {
            $0.identifier?.rawValue == "AZipMainWindow"
        }
        ExtractionWindowController.shared.show(over: mainWindow)

        // 必须脱离主 actor：解压循环里的目录统计是同步 I/O，
        // 跑在 MainActor 上会把界面完全卡死（表现为一直停在「准备中」）。
        let flag = cancelFlag
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await ArchiveExtractor.extract(
                    archiveURL: url,
                    to: destination,
                    progress: { value in
                        // 用主队列派发而非 Task：解压结束时应用会很快退出，
                        // 悬空的 MainActor Task 可能来不及执行，导致进度不动。
                        DispatchQueue.main.async {
                            guard let self, var current = self.job else { return }
                            current.progress = value
                            self.job = current
                            self.updatePanel(
                                url: url,
                                progress: value,
                                detail: String(
                                    format: NSLocalizedString("%d%% · 正在解压", comment: ""),
                                    Int((value * 100).rounded())
                                ),
                                finished: false
                            )
                        }
                    },
                    isCancelled: { flag.isSet }
                )

                await MainActor.run {
                    guard let self, var current = self.job else { return }
                    current.progress = 1
                    current.phase = .finished(destination)
                    self.job = current
                    self.elapsedTask?.cancel()
                    NSSound(named: NSSound.Name("Submarine"))?.play()
                    self.scheduleTermination(after: 1.2) {
                        if case .finished = $0 { return true }
                        return false
                    }

                    // 用户显式勾选「解压后删除压缩包」时才动原文件，
                    // 且只移到废纸篓（可恢复），不做不可逆删除。
                    if UserDefaults.standard.bool(forKey: "deleteArchiveAfterExtraction") {
                        var trashed: NSURL?
                        try? FileManager.default.trashItem(
                            at: url,
                            resultingItemURL: &trashed
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self, var current = self.job else { return }
                    if case ArchiveError.cancelled = error {
                        current.phase = .cancelled
                        self.scheduleTermination(after: 0.6) {
                            if case .cancelled = $0 { return true }
                            return false
                        }
                    } else {
                        current.phase = .failed(error.localizedDescription)
                    }
                    self.job = current
                }
            }
        }
    }

    private var elapsedTask: Task<Void, Never>?

    /// 解压过程中每秒刷新「已用时间」，配合不确定进度条。
    private func startElapsedTimer(url: URL) {
        elapsedTask?.cancel()
        elapsedTask = Task { @MainActor [weak self] in
            var seconds = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.job != nil else { return }
                seconds += 1
                self.updatePanel(
                    url: url,
                    progress: 0,
                    detail: String(
                        format: NSLocalizedString("正在解压… 已用 %d 秒", comment: ""),
                        seconds
                    ),
                    finished: false,
                    indeterminate: true
                )
            }
        }
    }

    func cancel() {
        cancelFlag.set()
    }

    private func updatePanel(
        url: URL,
        progress: Double,
        detail: String,
        finished: Bool,
        indeterminate: Bool = false
    ) {
        let line = "panel p=\(Int(progress * 100))% \(detail)\n"
        if let h = FileHandle(forWritingAtPath: "/tmp/azip-extract.log") {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile()
        }
        TaskPanelModel.shared.update(
            TaskPanelState(
                kind: .extracting,
                iconURL: url,
                title: String(
                    format: NSLocalizedString("AZip - 正在解压缩 %@", comment: ""),
                    url.lastPathComponent
                ),
                detail: detail,
                progress: progress,
                isFinished: finished,
                isIndeterminate: indeterminate
            )
        )
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
