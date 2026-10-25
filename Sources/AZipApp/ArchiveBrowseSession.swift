import AppKit
import Foundation
import SwiftUI
import AZipCore

/// 压缩包浏览会话：只解压用户点开/拖出的单个文件，不落地整个包。
@MainActor
final class ArchiveBrowseSession: ObservableObject {
    static let shared = ArchiveBrowseSession()

    @Published private(set) var archiveURL: URL?
    @Published private(set) var entries: [ArchiveEntry] = []
    @Published private(set) var currentPath: String = ""
    @Published private(set) var isLoading = false
    @Published var errorText: String?
    @Published private(set) var isExtractingAll = false

    private var tempDirectory: URL?
    private var cancelFlag = CancelFlag()

    var isActive: Bool { archiveURL != nil }

    var archiveName: String { archiveURL?.lastPathComponent ?? "" }

    /// 当前目录下的直接子项，目录在前、其余按名称排序。
    var visibleEntries: [ArchiveEntry] {
        entries
            .filter { $0.parentPath == currentPath }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    var canGoUp: Bool { !currentPath.isEmpty }

    // MARK: - 打开与导航

    func open(_ url: URL) {
        archiveURL = url
        currentPath = ""
        entries = []
        errorText = nil
        isLoading = true

        Task {
            do {
                let list = try await ArchiveReader.list(url)
                guard self.archiveURL == url else { return }
                self.entries = list
                self.isLoading = false
            } catch {
                guard self.archiveURL == url else { return }
                self.isLoading = false
                self.errorText = error.localizedDescription
            }
        }
    }

    func enter(_ entry: ArchiveEntry) {
        guard entry.isDirectory else {
            openEntry(entry)
            return
        }
        currentPath = entry.path.hasSuffix("/")
            ? String(entry.path.dropLast())
            : entry.path
    }

    func goUp() {
        guard canGoUp else { return }
        currentPath = (currentPath as NSString).deletingLastPathComponent
        if currentPath == "." { currentPath = "" }
    }

    func close() {
        archiveURL = nil
        entries = []
        currentPath = ""
        errorText = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
            self.tempDirectory = nil
        }
    }

    // MARK: - 单个条目

    /// 解压单个条目并交给系统打开。
    func openEntry(_ entry: ArchiveEntry) {
        guard let archiveURL else { return }
        Task {
            do {
                let directory = try workingDirectory()
                let extracted = try await ArchiveReader.extract(
                    entry: entry, from: archiveURL, to: directory
                )
                NSWorkspace.shared.open(extracted)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    /// 为拖拽准备条目：返回临时目录中的文件 URL（必要时先解压）。
    func prepareForDrag(_ entry: ArchiveEntry) async -> URL? {
        guard let archiveURL else { return nil }
        do {
            let directory = try workingDirectory()
            return try await ArchiveReader.extract(
                entry: entry, from: archiveURL, to: directory
            )
        } catch {
            errorText = error.localizedDescription
            return nil
        }
    }

    private func workingDirectory() throws -> URL {
        if let tempDirectory { return tempDirectory }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("azip-browse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempDirectory = directory
        return directory
    }

    // MARK: - 全部解压

    /// 解压到 `<parent>/<压缩包名>/`，进度复用通用浮窗。
    func extractAll(to parent: URL) {
        guard let archiveURL, !isExtractingAll else { return }
        let destination = parent.appendingPathComponent(
            (archiveURL.lastPathComponent as NSString).deletingPathExtension
        )
        cancelFlag.reset()
        isExtractingAll = true

        TaskPanelModel.shared.update(
            TaskPanelState(
                kind: .extracting,
                iconURL: archiveURL,
                title: String(
                    format: NSLocalizedString("AZip - 正在解压缩 %@", comment: ""),
                    archiveURL.lastPathComponent
                ),
                detail: NSLocalizedString("准备中…", comment: ""),
                progress: 0,
                isIndeterminate: true
            )
        )
        let mainWindow = NSApp.windows.first {
            $0.identifier?.rawValue == "AZipMainWindow"
        }
        ExtractionWindowController.shared.show(over: mainWindow)

        let flag = cancelFlag
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await ArchiveExtractor.extract(
                    archiveURL: archiveURL,
                    to: destination,
                    progress: { _ in },
                    isCancelled: { flag.isSet }
                )
                await MainActor.run {
                    self?.finishExtraction(success: true, destination: destination)
                }
            } catch {
                await MainActor.run {
                    self?.finishExtraction(success: false, destination: destination)
                }
            }
        }
    }

    private func finishExtraction(success: Bool, destination: URL) {
        isExtractingAll = false
        TaskPanelModel.shared.update(nil)
        ExtractionWindowController.shared.close()
        NSApp.windows.first { $0.identifier?.rawValue == "AZipMainWindow" }?
            .makeKeyAndOrderFront(nil)
        if success {
            NSSound(named: NSSound.Name("Submarine"))?.play()
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } else {
            errorText = NSLocalizedString("解压失败", comment: "")
        }
    }

    func cancelExtraction() {
        cancelFlag.set()
    }
}
