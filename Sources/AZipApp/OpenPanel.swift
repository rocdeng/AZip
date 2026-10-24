import AppKit
import UniformTypeIdentifiers

enum OpenPanel {
    @MainActor
    static func openDMG(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType("public.disk-image")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
}
