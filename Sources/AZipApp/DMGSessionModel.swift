import AppKit
import Foundation
import SwiftUI
import AZipCore

enum SessionState: Sendable {
    case idle
    case mounting
    case browsing(entries: [VolumeEntry], layout: DMGWindowLayout?)
    case installing(app: URL, progress: Double)
    case failed(String)
}

struct BannerMessage: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let isError: Bool
}

/// 多个 `.app` 时的选择面板数据源。
struct AppSelection: Identifiable, Sendable {
    let id = UUID()
    let entries: [VolumeEntry]
}

/// 同名覆盖确认面板数据源。
struct ConflictRequest: Identifiable, Sendable {
    let id = UUID()
    let appURL: URL
}

@MainActor
final class DMGSessionModel: ObservableObject {
    static let shared = DMGSessionModel()

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var mount: MountResult?
    @Published private(set) var dmgName: String = "AZip"
    @Published private(set) var navigationStack: [URL] = []
    @Published var banner: BannerMessage?
    @Published var showAssociationSheet = false
    @Published var pendingApps: AppSelection?
    @Published var pendingConflict: ConflictRequest?

    private var layout: DMGWindowLayout?
    private var associationPromptShown = false

    var currentDirectory: URL? {
        navigationStack.last ?? mount?.mountPoint
    }

    var currentDirectoryName: String {
        if navigationStack.isEmpty {
            return dmgName
        }
        return navigationStack.last?.lastPathComponent ?? dmgName
    }

    var rootApplications: [VolumeEntry] {
        guard case let .browsing(entries, _) = state else { return [] }
        return VolumeScanner.applications(in: entries)
    }

    // MARK: - Lifecycle

    func offerAssociationIfNeeded() {
        guard !associationPromptShown else { return }
        associationPromptShown = true
        guard !UserDefaults.standard.bool(forKey: "didOfferFileAssociation") else { return }
        showAssociationSheet = true
    }

    func open(dmgURL: URL) {
        Task { await performOpen(dmgURL) }
    }

    private func performOpen(_ dmgURL: URL) async {
        await detachCurrent()
        dmgName = dmgURL.lastPathComponent
        navigationStack = []
        layout = nil
        state = .mounting

        do {
            let result = try await DiskImageMounter.attach(dmgURL)
            mount = result

            let document = readDSStore(at: result.mountPoint)
            let parsedLayout = DMGWindowLayout.make(mountPoint: result.mountPoint, document: document)
            layout = parsedLayout

            let entries = try VolumeScanner.scan(directory: result.mountPoint)
            state = .browsing(entries: entries, layout: parsedLayout)

            if let parsedLayout {
                resizeWindow(to: parsedLayout.contentSize)
            }
        } catch {
            mount = nil
            state = .failed(describe(error))
        }
    }

    func enter(_ entry: VolumeEntry) {
        switch entry.kind {
        case .folder, .application:
            guard entry.kind == .folder else {
                requestInstall(entry)
                return
            }
            Task { await performEnter(entry.url) }
        case .file, .symbolicLink:
            NSWorkspace.shared.open(entry.url)
        }
    }

    private func performEnter(_ url: URL) async {
        do {
            let entries = try VolumeScanner.scan(directory: url)
            navigationStack.append(url)
            state = .browsing(entries: entries, layout: nil)
        } catch {
            banner = BannerMessage(text: "无法打开文件夹", isError: true)
        }
    }

    func goUp() {
        guard !navigationStack.isEmpty else { return }
        navigationStack.removeLast()
        reloadCurrent()
    }

    func goBackToRoot() {
        navigationStack.removeAll()
        reloadCurrent()
    }

    private func reloadCurrent() {
        guard let directory = currentDirectory else { return }
        do {
            let entries = try VolumeScanner.scan(directory: directory)
            let activeLayout = navigationStack.isEmpty ? layout : nil
            state = .browsing(entries: entries, layout: activeLayout)
        } catch {
            banner = BannerMessage(text: "无法读取目录", isError: true)
        }
    }

    // MARK: - Install

    func requestInstall(_ app: VolumeEntry) {
        let candidates = rootApplications
        if candidates.count > 1 {
            pendingApps = AppSelection(entries: candidates)
        } else {
            startInstall(app.url, overwrite: false)
        }
    }

    /// 由选择面板直接指定要安装的应用（不再重复弹面板）。
    func installDirectly(_ entry: VolumeEntry) {
        pendingApps = nil
        startInstall(entry.url, overwrite: false)
    }

    func confirmConflict() {
        guard let request = pendingConflict else { return }
        pendingConflict = nil
        startInstall(request.appURL, overwrite: true)
    }

    private func startInstall(_ appURL: URL, overwrite: Bool) {
        state = .installing(app: appURL, progress: 0)
        Task {
            do {
                let installed = try await AppInstaller.install(
                    InstallRequest(
                        sourceApp: appURL,
                        targetDirectory: URL(fileURLWithPath: "/Applications"),
                        overwrite: overwrite
                    ),
                    progress: { value in
                        Task { @MainActor in
                            self.state = .installing(app: appURL, progress: value)
                        }
                    }
                )
                banner = BannerMessage(text: "已安装 \(installed.lastPathComponent)", isError: false)
                reloadCurrent()
                await detachCurrent()
                state = .idle
            } catch InstallError.conflict(_) {
                state = .installing(app: appURL, progress: 0)
                pendingConflict = ConflictRequest(appURL: appURL)
                reloadCurrent()
            } catch {
                banner = BannerMessage(text: describe(error), isError: true)
                reloadCurrent()
            }
        }
    }

    // MARK: - Teardown

    func closeSession() {
        Task { await detachCurrent() }
    }

    private func detachCurrent() async {
        guard let mount else { return }
        self.mount = nil
        try? await DiskImageMounter.detach(mount)
    }

    // MARK: - Helpers

    private func readDSStore(at mountPoint: URL) -> DSStoreDocument {
        let url = mountPoint.appendingPathComponent(".DS_Store")
        guard let data = try? Data(contentsOf: url) else { return DSStoreDocument() }
        return DSStoreReader.parse(data)
    }

    private func resizeWindow(to size: CGSize) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else { return }
        window.setContentSize(NSSize(width: size.width, height: size.height))
        window.center()
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case MountError.toolFailed(_, let message):
            return "无法打开该磁盘映像。\n\(message)"
        case MountError.noMountPointFound:
            return "无法打开该磁盘映像，文件可能已损坏。"
        case InstallError.targetNotWritable:
            return "没有权限写入应用程序文件夹，请在访达中手动拖拽安装。"
        case InstallError.copyFailed(let message):
            return "安装失败：\(message)"
        case InstallError.moveFailed(let message):
            return "安装失败：\(message)"
        case InstallError.invalidSource:
            return "所选项目不是有效的应用程序。"
        default:
            return error.localizedDescription
        }
    }
}
