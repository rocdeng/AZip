// AZip — 语言设置与运行时本地化查表
//
// 默认语言：**跟随系统**（`system`）。
// 用户在「设置 → 界面语言」里切换后，立即切换当前进程使用的 `.lproj` 语言包，
// 界面无需重启即可重绘生效。

import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case zhHans = "zh-Hans"
    case en = "en"

    public var id: String { rawValue }

    private static let storageKey = "appLanguage"

    /// 显示名称：具体语言固定用该语言自身的名字（避免切错语言后找不回来），「跟随系统」随当前语言切换。
    public var displayName: String {
        switch self {
        case .system: return NSLocalizedString("跟随系统", comment: "")
        case .zhHans: return "简体中文"
        case .en:     return "English"
        }
    }

    /// 当前选择的语言设置（默认跟随系统 `.system`）
    public static var current: AppLanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: storageKey),
               let lang = AppLanguage(rawValue: raw) {
                return lang
            }
            return .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            switch newValue {
            case .system:
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            case .zhHans, .en:
                UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
            }
        }
    }

    /// 实际生效的 `.lproj` 目录名（`zh-Hans` 或 `en`）
    public var resolvedCode: String {
        switch self {
        case .zhHans:
            return "zh-Hans"
        case .en:
            return "en"
        case .system:
            return Self.systemLanguageCode
        }
    }

    public var locale: Locale {
        Locale(identifier: resolvedCode)
    }

    /// 读取 macOS 系统的首选语言（绕开本应用 UserDefaults 里可能写过的 AppleLanguages）
    private static var systemLanguageCode: String {
        let globalLangs = CFPreferencesCopyValue(
            "AppleLanguages" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String]
        let candidates = globalLangs ?? Locale.preferredLanguages
        for tag in candidates {
            let lower = tag.lowercased()
            if lower.hasPrefix("zh") {
                return "zh-Hans"
            }
            if lower.hasPrefix("en") {
                return "en"
            }
        }
        return "zh-Hans"
    }

    /// 对应 `.lproj` 子包（找不到时回退 `Bundle.main`）
    public var bundle: Bundle {
        let code = resolvedCode
        let candidates = [Bundle.main, Bundle(for: BundleToken.self)]
        for candidate in candidates {
            if let path = candidate.path(forResource: code, ofType: "lproj"),
               let b = Bundle(path: path) {
                return b
            }
            if let path = candidate.path(forResource: code.lowercased(), ofType: "lproj"),
               let b = Bundle(path: path) {
                return b
            }
        }
        return .main
    }
}

private final class BundleToken {}

/// 覆盖模块内的 `NSLocalizedString`，使其直接按 `AppLanguage.current` 查表，
/// 在「设置」里切换语言后无需重启应用，整个界面立即重绘生效。
public func NSLocalizedString(
    _ key: String,
    tableName: String? = nil,
    bundle: Bundle = .main,
    value: String = "",
    comment: String
) -> String {
    let targetBundle = (bundle == .main) ? AppLanguage.current.bundle : bundle
    let fallback = value.isEmpty ? key : value
    return targetBundle.localizedString(forKey: key, value: fallback, table: tableName)
}
