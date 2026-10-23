import Foundation

public enum LaunchServicesRegistrar {
    private static let toolPath =
        "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    /// 尽力而为：工具不存在或执行失败都不影响安装结果。
    public static func register(_ appURL: URL) async {
        guard FileManager.default.isExecutableFile(atPath: toolPath) else { return }
        _ = try? await ProcessRunner.run(toolPath, ["-f", appURL.path], timeoutSeconds: 30)
    }
}
