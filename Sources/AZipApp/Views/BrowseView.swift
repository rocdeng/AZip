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
                .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 11))
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
        HStack(spacing: 10) {
            Image(nsImage: icon(for: entry))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)

            Text(entry.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if !entry.isDirectory {
                Text(sizeText(entry.size))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }

            if let date = entry.modified {
                Text(dateText(date))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.accentColor.opacity(selectedPath == entry.path ? 0.20 : 0))
                .padding(.horizontal, 8)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPath = entry.path
        }
        .onTapGesture(count: 2) {
            session.enter(entry)
        }
        .onDrag {
            if let url = session.dragURL(for: entry) {
                return NSItemProvider(contentsOf: url) ?? NSItemProvider()
            }
            return NSItemProvider()
        }
        .contextMenu {
            if !entry.isDirectory {
                Button(NSLocalizedString("打开", comment: "")) {
                    session.openEntry(entry)
                }
                Button(NSLocalizedString("导出到…", comment: "")) {
                    export(entry)
                }
            }
        }
        .help(entry.isDirectory
            ? NSLocalizedString("双击进入文件夹", comment: "")
            : NSLocalizedString("双击打开", comment: "")
        )
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button {
                chooseDestination()
            } label: {
                Label(NSLocalizedString("解压缩到…", comment: ""), systemImage: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassCapsule()
            }
            .buttonStyle(.plain)
            .disabled(session.isExtractingAll)

            Spacer()

            Button(action: onClose) {
                Text(NSLocalizedString("关闭", comment: ""))
                    .font(.system(size: 12, weight: .medium))
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
        if entry.isDirectory {
            return NSWorkspace.shared.icon(for: .folder)
        }
        let ext = (entry.name as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: type)
        }
        return NSWorkspace.shared.icon(for: .data)
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
