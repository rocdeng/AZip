import AppKit
import AZipCore
import SwiftUI

/// 独立设置窗口（⌘,）以及直接启动时主窗口的内容。
struct SettingsView: View {
    var body: some View {
        AssociationSettingsPane()
            .frame(width: 460, height: 430)
    }
}

struct AssociationSettingsPane: View {
    @State private var states: [String: Bool] = [:]
    @State private var message: String?

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.dengpeng.AZip"
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("文件关联") {
                    ForEach(FileAssociationService.supportedTypes) { type in
                        Toggle(isOn: binding(for: type)) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(type.label)
                                Text(type.fileExtensions.map { ".\($0)" }.joined(separator: "  "))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                }

                Section {
                    Text("勾选后，双击对应文件将由 AZip 打开。压缩格式的打开与解压功能将在后续版本提供。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("全部恢复为系统默认") {
                        restoreAll()
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
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
                        message = "已将 \(type.label) 关联到 AZip"
                    } else {
                        try FileAssociationService.restoreSystemDefault(for: type)
                        message = "已将 \(type.label) 恢复为系统默认"
                    }
                } catch {
                    message = "设置失败：\(error.localizedDescription)"
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

    private func restoreAll() {
        var failures: [String] = []
        for type in FileAssociationService.supportedTypes {
            do {
                try FileAssociationService.restoreSystemDefault(for: type)
            } catch {
                failures.append(type.label)
            }
        }
        message = failures.isEmpty
            ? "已全部恢复为系统默认"
            : "以下格式恢复失败：\(failures.joined(separator: "、"))"
        refresh()
    }
}
