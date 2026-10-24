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
            } catch {
                guard var current = job else { return }
                if case ArchiveError.cancelled = error {
                    current.phase = .cancelled
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

    func dismiss() {
        guard let job else { return }
        if case .running = job.phase {
            cancelFlag.set()
            return
        }
        self.job = nil
    }

    func revealInFinder() {
        guard case let .finished(url) = job?.phase else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        job = nil
    }
}
