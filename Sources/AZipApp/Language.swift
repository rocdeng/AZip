import AZipCore
import Foundation

/// 转发到 `AZipCore.NSLocalizedString`，以模块内同名函数遮蔽 `Foundation.NSLocalizedString`，
/// 让 `AZipApp` 内的所有 `NSLocalizedString` 调用直接走 `AppLanguage.current.bundle`。
func NSLocalizedString(
    _ key: String,
    tableName: String? = nil,
    bundle: Bundle = .main,
    value: String = "",
    comment: String
) -> String {
    AZipCore.NSLocalizedString(
        key,
        tableName: tableName,
        bundle: bundle,
        value: value,
        comment: comment
    )
}
