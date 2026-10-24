import AppKit
import AZipCore
import SwiftUI

/// 独立设置窗口（⌘,）以及直接启动时主窗口的内容。
struct SettingsView: View {
    var body: some View {
        AssociationSettingsPane()
            .frame(width: 520, height: 600)
    }
}

struct AssociationSettingsPane: View {
    @ObservedObject private var model = DMGSessionModel.shared
    @State private var states: [String: Bool] = [:]
    @State private var message: String?
    @State private var showsAbout = false
    @AppStorage("deleteArchiveAfterExtraction") private var deleteArchiveAfterExtraction = false

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.dengpeng.AZip"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("文件关联", comment: ""))
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 22)
                .padding(.top, 26)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(
                    Array(FileAssociationService.supportedTypes.enumerated()),
                    id: \.element.id
                ) { index, type in
                    row(for: type)
                    if index < FileAssociationService.supportedTypes.count - 1 {
                        Divider()
                            .opacity(0.12)
                            .padding(.leading, 54)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            )
            .padding(.horizontal, 18)

            optionRow

            Spacer(minLength: 0)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showsAbout) {
            AboutView()
                .id(model.language)
                .environment(\.locale, model.language.locale)
        }
        .onChange(of: model.language) { _, _ in
            message = nil
        }
        .onAppear(perform: refresh)
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
        ) { _ in
            refresh()
        }
    }

    private func row(for type: FileTypeAssociation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName(for: type))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(type.label)
                    .font(.system(size: 12))
                Text(type.fileExtensions.map { ".\($0)" }.joined(separator: "  "))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: binding(for: type))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var optionRow: some View {
        HStack(spacing: 12) {
            Toggle(
                NSLocalizedString("解压后删除压缩包", comment: ""),
                isOn: $deleteArchiveAfterExtraction
            )
            .toggleStyle(.checkbox)
            .font(.system(size: 11))

            Spacer()

            HStack(spacing: 6) {
                Text(NSLocalizedString("界面语言", comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Picker("", selection: $model.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("勾选后，双击对应文件将由 AZip 打开。", comment: ""))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(NSLocalizedString("全部关联", comment: "")) {
                    associateAll()
                }
                .controlSize(.small)

                Button(NSLocalizedString("全部恢复为系统默认", comment: "")) {
                    restoreAll()
                }
                .controlSize(.small)

                if let message {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(NSLocalizedString("关于 AZip", comment: "")) {
                    showsAbout = true
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func symbolName(for type: FileTypeAssociation) -> String {
        switch type.id {
        case "com.apple.disk-image-udif": return "opticaldisc"
        case "public.zip-archive": return "doc.zipper"
        case "public.tar-archive", "org.gnu.gnu-zip-tar-archive": return "shippingbox"
        default: return "archivebox"
        }
    }

    private func binding(for type: FileTypeAssociation) -> Binding<Bool> {
        Binding(
            get: {
                states[type.id]
                    ?? FileAssociationService.isDefault(bundleID: bundleID, for: type)
            },
            set: { newValue in
                do {
                    if newValue {
                        try FileAssociationService.setDefault(bundleID: bundleID, for: type)
                        message = String(
                            format: NSLocalizedString("已将 %@ 关联到 AZip", comment: ""),
                            type.label
                        )
                    } else {
                        try FileAssociationService.restoreSystemDefault(for: type)
                        message = String(
                            format: NSLocalizedString("已将 %@ 恢复为系统默认", comment: ""),
                            type.label
                        )
                    }
                } catch {
                    message = String(
                        format: NSLocalizedString("设置失败：%@", comment: ""),
                        error.localizedDescription
                    )
                }
                refresh()
            }
        )
    }

    private func refresh() {
        var updated: [String: Bool] = [:]
        for type in FileAssociationService.supportedTypes {
            updated[type.id] = FileAssociationService.isDefault(bundleID: bundleID, for: type)
        }
        states = updated
    }

    private func associateAll() {
        var failures: [String] = []
        for type in FileAssociationService.supportedTypes {
            do {
                try FileAssociationService.setDefault(bundleID: bundleID, for: type)
            } catch {
                failures.append(type.label)
            }
        }
        let separator = NSLocalizedString("、", comment: "")
        message = failures.isEmpty
            ? NSLocalizedString("已全部关联到 AZip", comment: "")
            : String(
                format: NSLocalizedString("以下格式关联失败：%@", comment: ""),
                failures.joined(separator: separator)
            )
        refresh()
    }

    private func restoreAll() {
        var failures: [String] = []
        for type in FileAssociationService.supportedTypes {
            do {
                try FileAssociationService.restoreSystemDefault(for: type)
            } catch {
                failures.append(type.label)
            }
        }
        let separator = NSLocalizedString("、", comment: "")
        message = failures.isEmpty
            ? NSLocalizedString("已全部恢复为系统默认", comment: "")
            : String(
                format: NSLocalizedString("以下格式恢复失败：%@", comment: ""),
                failures.joined(separator: separator)
            )
        refresh()
    }
}
