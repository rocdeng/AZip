import AppKit
import AZipCore
import SwiftUI
import UniformTypeIdentifiers

/// 压缩包浏览界面：列表展示内容，双击进入目录或打开文件，底部可整体解压。
struct BrowseView: View {
    @ObservedObject var session: ArchiveBrowseSession
    var onClose: () -> Void

    @State private var selectedPath: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.12)
            content
            bottomBar
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                session.goUp()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 22)
                    .glassCapsule()
            }
            .buttonStyle(.plain)
            .disabled(!session.canGoUp)
            .opacity(session.canGoUp ? 1 : 0.45)
            .help(NSLocalizedString("上一级", comment: ""))

            Text(pathText)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if session.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var pathText: String {
        let suffix = session.currentPath.isEmpty
            ? ""
            : " / " + session.currentPath.replacingOccurrences(of: "/", with: " / ")
        return session.archiveName + suffix
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let error = session.errorText {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.visibleEntries.isEmpty && !session.isLoading {
            Text(NSLocalizedString("这个文件夹是空的", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(session.visibleEntries) { entry in
                        row(for: entry)
                        Divider().opacity(0.08)
                    }
                }
            }
        }
    }

    private func row(for entry: ArchiveEntry) -> some View {
        BrowseRow(
            entry: entry,
            session: session,
            isSelected: selectedPath == entry.path,
            onTap: { selectedPath = entry.path },
            onDoubleTap: { session.enter(entry) },
            onOpen: { session.openEntry(entry) },
            onExport: { export(entry) }
        )
        .equatable()
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button {
                chooseDestination()
            } label: {
                Label(NSLocalizedString("解压缩到…", comment: ""), systemImage: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassCapsule()
            }
            .buttonStyle(.plain)
            .disabled(session.isExtractingAll)

            Spacer()

            Button(action: onClose) {
                Text(NSLocalizedString("关闭", comment: ""))
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassCapsule()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("解压到此处", comment: "")
        panel.message = NSLocalizedString(
            "选择目标文件夹，压缩包内容会解压到以压缩包命名的子文件夹里。",
            comment: ""
        )
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        session.extractAll(to: directory)
    }

    private func export(_ entry: ArchiveEntry) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = NSLocalizedString("导出", comment: "")
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        Task {
            guard let extracted = await session.prepareForDrag(entry) else { return }
            let destination = directory.appendingPathComponent(entry.name)
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: extracted, to: destination)
        }
    }

    // MARK: - Formatting

    private func icon(for entry: ArchiveEntry) -> NSImage {
        BrowseIconCache.icon(for: entry)
    }

    private func sizeText(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}


/// 统一的毛玻璃胶囊按钮外观。
private struct GlassCapsuleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule().fill(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    )
            )
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.85), .white.opacity(0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}

extension View {
    func glassCapsule() -> some View {
        modifier(GlassCapsuleStyle())
    }
}


/// 图标按「目录 / 扩展名」缓存：NSWorkspace 取图标开销不小，
/// 列表滚动和选中重绘时会被反复调用。
@MainActor
enum BrowseIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for entry: ArchiveEntry) -> NSImage {
        if entry.isDirectory {
            return cached("__folder__") { NSWorkspace.shared.icon(for: .folder) }
        }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        return cached(ext) {
            if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
                return NSWorkspace.shared.icon(for: type)
            }
            return NSWorkspace.shared.icon(for: .data)
        }
    }

    private static func cached(_ key: String, make: () -> NSImage) -> NSImage {
        if let image = cache[key] { return image }
        let image = make()
        cache[key] = image
        return image
    }
}


/// 单行条目。独立成 View 并实现 Equatable，点击选中时只重绘这一行。
private struct BrowseRow: View, Equatable {
    let entry: ArchiveEntry
    let session: ArchiveBrowseSession
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onOpen: () -> Void
    let onExport: () -> Void

    nonisolated static func == (lhs: BrowseRow, rhs: BrowseRow) -> Bool {
        lhs.entry == rhs.entry && lhs.isSelected == rhs.isSelected
    }

    // session 是单例引用，不参与相等性比较。

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: BrowseIconCache.icon(for: entry))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .onHover { hovering in
                    if hovering {
                        FilePreviewer.shared.beginHover(entry: entry, session: session)
                    } else {
                        FilePreviewer.shared.endHover()
                    }
                }

            Text(entry.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if !entry.isDirectory {
                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 76, alignment: .trailing)
            }

            if let date = entry.modified {
                Text(formatted(date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 112, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.accentColor.opacity(isSelected ? 0.20 : 0))
                .padding(.horizontal, 8)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onTapGesture(count: 2, perform: onDoubleTap)
        .contextMenu {
            if !entry.isDirectory {
                Button(NSLocalizedString("打开", comment: ""), action: onOpen)
                Button(NSLocalizedString("导出到…", comment: ""), action: onExport)
            }
        }
        .help(entry.isDirectory
            ? NSLocalizedString("双击进入文件夹", comment: "")
            : NSLocalizedString("双击打开", comment: "")
        )
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
