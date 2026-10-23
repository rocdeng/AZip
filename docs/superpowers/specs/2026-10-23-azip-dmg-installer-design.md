# AZip — DMG 关联与一键安装 设计文档

- 日期：2026-10-23
- 状态：待实现
- 首期范围：仅 DMG 链路（压缩/解压不在本期）

## 1. 目标

做一个 macOS 应用，接管 `.dmg` 文件：双击 DMG 后由本应用挂载并原生还原地展示其内容（含作者自定义背景与图标布局），并提供「安装应用」按钮，一键把 `.app` 复制到 `/Applications` 并移除隔离属性，使首次启动不出现「已损坏，是否移到废纸篓」对话框。

### 成功标准

| 编号 | 标准 | 验证方式 |
|---|---|---|
| S1 | 双击 `.dmg` 由 AZip 打开 | Finder 中双击测试 dmg |
| S2 | 带自定义背景的 DMG，背景图与图标位置与原生命令 `hdiutil` + Finder 打开一致 | 与 Finder 打开同一 dmg 逐项比对 |
| S3 | 点「安装应用」后 `/Applications` 出现该 app，且 xattr 无 `com.apple.quarantine` | `xattr -p com.apple.quarantine` 返回空 |
| S4 | 安装后的 app 首次启动无 Gatekeeper「移到废纸篓」弹窗 | 实际启动 |
| S5 | 安装成功后自动卸载挂载卷，原 dmg 文件保留 | `ls /Volumes` 无残留 |
| S6 | 同名 app 已存在时弹窗询问，取消则不做任何改动 | 人工验证 |
| S7 | 全程不删除用户文件（唯一例外：用户确认覆盖时，旧版移入废纸篓） | 代码审查 + 人工验证 |

## 2. 范围

### 首期要做

- `.dmg` 文件关联（首启对话框 + 设置页可改）
- `hdiutil` 挂载与卸载
- DMG 内容浏览（根目录按 `.DS_Store` 布局还原；子目录用图标网格）
- 一键安装 `.app` 到 `/Applications`
- 安装后递归移除 `com.apple.quarantine`
- 同名冲突确认与安全回滚
- 毛玻璃悬浮窗口风格
- 启动时检测上次安装中断遗留的备份目录并提示用户（只提示，不自动处理）

### 首期不做

| 项 | 原因 |
|---|---|
| 压缩 / 解压 | 后续版本 |
| zip/7z/rar 等格式 | 后续版本 |
| 公证 / Developer ID 签名 | 后续版本 |
| admin 提权安装 | 首期遇到权限错误仅提示并引导手动安装 |
| 应用自更新 | 首期不做 |
| DMG 内文件的解包提取 | 双击文件用系统默认程序打开即可 |

## 3. 技术选型

| 项 | 决定 |
|---|---|
| 语言 | Swift 6（语言模式 Swift 6，UI 层 `@MainActor`，Core 层值类型 `Sendable`） |
| UI | SwiftUI 为主 + AppKit 桥（`NSVisualEffectView`、`NSWorkspace`、`NSWindow` 配置） |
| 最低系统 | macOS 14.0 |
| 工程生成 | XcodeGen（`project.yml`），构建用 `xcodebuild` |
| 沙盒 | **关闭**（需写 `/Applications` 与修改 xattr） |
| 签名 | 本地自签证书 `AZip Local Code Signing`，关闭 hardened runtime；保留后续换 Developer ID + 公证的余地 |
| 第三方依赖 | **无** |
| 挂载 | `hdiutil attach -plist`（子进程） |
| 拷贝 | `ditto`（保留权限、符号链接、扩展属性） |

### 为什么用 `hdiutil` 而不是 DiskArbitration

`hdiutil -plist` 输出结构稳定、可解析、失败信息可读；DiskArbitration 需要更多样板代码且错误码更晦涩。首期以可维护性优先。

## 4. 工程结构

```
AZip/
├─ project.yml                         # XcodeGen 工程定义
├─ Sources/
│  ├─ AZipCore/                        # 纯逻辑，无 UI，全部可单测
│  │  ├─ DiskImageMounter.swift        # attach/detach + plist 解析
│  │  ├─ DiskImageSession.swift        # 挂载会话（挂载点、设备、生命周期）
│  │  ├─ VolumeEntry.swift             # 目录条目模型
│  │  ├─ DSStoreReader.swift           # Bud1 / .DS_Store 解析
│  │  ├─ DMGWindowLayout.swift         # 布局模型与坐标换算
│  │  ├─ AppInstaller.swift            # 拷贝 / 冲突 / 回滚
│  │  ├─ QuarantineCleaner.swift       # 递归移除隔离属性
│  │  ├─ LaunchServicesRegistrar.swift # lsregister 注册
│  │  ├─ FileAssociation.swift         # 设为 .dmg 默认打开程序
│  │  ├─ InstallTargets.swift          # 目标目录注入（生产=/Applications，测试=临时目录）
│  │  └─ ProcessRunner.swift           # 子进程统一封装（超时、stdout/stderr 捕获）
│  └─ AZipApp/                         # SwiftUI 应用层
│     ├─ AZipApp.swift                 # @main
│     ├─ AppDelegate.swift             # 接收 Finder 打开的 dmg URL
│     ├─ DMGSessionModel.swift         # @MainActor 视图状态机
│     ├─ Views/
│     │  ├─ RootWindow.swift           # 毛玻璃容器 + 窗口配置
│     │  ├─ VisualEffectBackground.swift
│     │  ├─ NavigationBar.swift        # 返回 / 上级 / 路径
│     │  ├─ LayoutContentView.swift    # 有 DS_Store 布局时的绝对定位视图
│     │  ├─ GridContentView.swift      # 无布局时的图标网格
│     │  ├─ FileTile.swift             # 条目视图（真实系统图标 + 拖拽）
│     │  ├─ BottomBar.swift            # 「安装应用」+ 进度
│     │  ├─ AssociationSheet.swift     # 首启文件关联弹窗
│     │  ├─ InstallTargetSheet.swift   # 多个 .app 时的选择
│     │  └─ InstallConflictSheet.swift # 同名覆盖确认
│     └─ Assets.xcassets
├─ Tests/
│  └─ AZipCoreTests/
│     ├─ Fixtures/
│     │  ├─ dsstore/                   # 真实 .DS_Store 样本
│     │  └─ hdiutil/                   # hdiutil -plist 输出样本
│     ├─ DSStoreReaderTests.swift
│     ├─ DiskImageMounterTests.swift
│     ├─ AppInstallerTests.swift
│     ├─ QuarantineCleanerTests.swift
│     └─ FileAssociationTests.swift
├─ Scripts/
│  ├─ build.sh                         # xcodegen + xcodebuild
│  ├─ make_test_dmg.sh                 # 造带/不带背景的测试 dmg
│  └─ integration_test.sh              # 全链路集成测试
└─ Resources/
   ├─ Info.plist
   └─ AZip.entitlements
```

## 5. 核心模块

### 5.1 DiskImageMounter

```swift
struct MountResult: Sendable {
    let mountPoint: URL      // /Volumes/xxx
    let deviceEntry: String  // /dev/disk4s1
    let volumeName: String
}

enum MountError: Error {
    case toolFailed(code: Int32, stderr: String)
    case noMountPointFound
    case alreadyMounted(URL)
}

func attach(dmgURL: URL) async throws -> MountResult
func detach(_ result: MountResult) async throws
```

- attach：`hdiutil attach <path> -plist -nobrowse -noautoopen -readonly`
  - `-nobrowse`：不向 Finder 暴露卷，避免用户看到两个入口
  - `-noautoopen`：不自动弹 Finder 窗口
  - `-readonly`：绝不允许写挂载卷
  - 解析 plist 的 `system-entities`，取带 `mount-point` 的项
- 挂载超时 60 秒，超时后强制 detach 并报错
- detach：先 `hdiutil detach <dev>`，失败再 `hdiutil detach <dev> -force`
- 幂等：重复 attach 同一 dmg 时先检测 `hdiutil info` 中是否已有该 image-path

### 5.2 DSStoreReader

`.DS_Store` 是 Bud1 二进制格式，结构：

1. Header 4 字节 magic `Bud1`
2. 4 字节 root block offset（大端）
3. 256 字节 block 偏移表
4. 各 block 内是记录序列：`filenameLen(4, BE) + filename(UTF-16BE) + code(4 ASCII) + type(4 ASCII) + dataLen(4, BE) + data`

解析产出：

```swift
struct DSStoreDocument: Sendable {
    var windowFrame: CGRect?              // 来自 bwsp / WindowBounds
    var iconSize: CGFloat?                // 来自 icvp / iconSize
    var textSize: CGFloat?                // 来自 icvp / textSize
    var backgroundColor: [CGFloat]?       // 来自 icvp / backgroundColor (RGBA 0-1)
    var backgroundAlias: Data?            // 来自 icvp / backgroundImageAlias
    var iconPositions: [String: CGPoint]  // 来自各条目 Iloc
}
```

支持的数据类型：`long`(4)、`shor`(4)、`bool`(1)、`blob`(4+len)、`type`(4+UTF-16)、`comp`(8)、`dutc`(8)。未知类型跳过并记录，不抛错。

**坐标单位待标定**：`Iloc` 的 blob 为 8 字节，社区实现对 x/y 的换算存在 `1/1000` 与直接点两种说法。实现时用 `Fixtures/dsstore/` 中的真实样本校准：以背景图尺寸为参照，反推系数并写成常量，并用单测锁定。这是本模块唯一需要实测确认的点。

### 5.3 DMGWindowLayout

```swift
struct DMGWindowLayout: Sendable {
    let contentSize: CGSize            // 来自 windowFrame.size，clamp 到 [480x320, 屏幕 90%]
    let backgroundImageURL: URL?       // 解析后的实际文件
    let backgroundColor: Color?
    let iconPositions: [String: CGPoint]  // 已换算到窗口坐标系
    let iconSize: CGFloat              // 默认 64，clamp 到 [48, 128]
}
```

背景图定位顺序：

1. alias 解析：`CFURLCreateBookmarkDataFromAliasRecord` → `URL(resolvingBookmarkData:)` → 取 `lastPathComponent` → 拼到 `<mountPoint>/.background/<name>`
2. 上述文件不存在 → `lastPathComponent` 拼到 `<mountPoint>/<name>`
3. 仍不存在 → 扫描 `<mountPoint>/.background/` 内第一张 `.png/.jpg/.jpeg/.tiff`
4. 全部失败 → 无背景图，回退网格模式

安全约束（重要）：alias 解析出的 URL 指向**原作者机器上的路径**，不可直接访问。只取文件名并强制拼接到当前挂载点下；任何解析结果若包含 `..` 或绝对路径越界，一律丢弃。

### 5.4 VolumeEntry 与内容扫描

```swift
struct VolumeEntry: Identifiable, Sendable {
    enum Kind: Sendable { case folder, application, symbolicLink, file }
    let id: URL
    let url: URL
    let name: String
    let kind: Kind
    let byteSize: Int64?
    let isHidden: Bool
}
```

扫描规则：

- 跳过 `.DS_Store`、`.background`、`.VolumeIcon.icns`、`.fseventsd`、`.Trashes`、`.Spotlight-V100`、`.TemporaryItems`、`.com.apple.timemachine.donotpresent`
- 跳过指向 `/Applications` 的符号链接（DMG 里那个 Applications 链接不展示为可点击项，也不计入「可安装应用」）
- `.app` 目录识别：`url.pathExtension == "app" && isDirectory`
- 文件大小取 `totalFileAllocatedSize`，目录不计算总大小（避免扫描大目录卡顿）
- 扫描在后台线程，结果一次性回传 `@MainActor`

### 5.5 AppInstaller

```swift
struct InstallRequest: Sendable {
    let sourceApp: URL
    let targetDirectory: URL   // 生产：/Applications
    let overwrite: Bool
}

enum InstallError: Error {
    case targetNotWritable(URL)
    case copyFailed(String)
    case rollbackFailed(String)
    case cancelled
}

func install(_ request: InstallRequest,
             progress: @Sendable (Double) -> Void) async throws -> URL
```

执行顺序（关键：任何一步失败都要能回到原状）：

| 步骤 | 动作 | 失败处理 |
|---|---|---|
| 1 | 检查 `targetDirectory` 可写 | 抛 `targetNotWritable`，UI 提示「在访达中显示 /Applications」 |
| 2 | 目标已存在且未确认覆盖 | 返回冲突，由 UI 弹窗；确认后带 `overwrite: true` 重入 |
| 3 | 用 `ditto` 拷到 `targetDirectory/.azip-staging-<uuid>/<name>.app` | 抛 `copyFailed`；清理 staging 目录 |
| 4 | 若覆盖：把旧 app `moveItem` 到 `targetDirectory/.azip-backup-<uuid>.app`（同卷原子改名） | 抛错，旧 app 未动 |
| 5 | 把 staging 内的 app `moveItem` 到最终路径 | 回滚：backup 改回原名，清理 staging |
| 6 | 递归移除 quarantine | 失败仅警告，不回滚（app 已就位） |
| 7 | `lsregister -f <finalPath>` | 失败仅警告 |
| 8 | 成功后把 backup `NSWorkspace.recycle` 到废纸篓 | 失败仅警告（用户可在 /Applications 看到残留备份并自行处理，UI 提示路径） |

进度：`ditto` 不提供进度，采用「目标大小采样轮询」估算（每 200ms 统计 staging 目录已分配大小 / 源 app 总大小），仅用于进度条，不参与判定。

目标目录由 `InstallTargets` 注入：生产环境为 `/Applications`，测试与集成测试传入临时目录，从而让 `AppInstaller` 无需任何 mock 即可被完整单测。

```swift
func pendingBackups() -> [URL]   // 返回 <target>/.azip-backup-* 列表，供启动时提示
```

当 DMG 根目录存在多个 `.app` 时，点「安装应用」先弹 `InstallTargetSheet` 列出全部候选（名称 + 图标 + 版本号），用户选中后再走冲突检查。

### 5.6 QuarantineCleaner

```swift
func removeQuarantine(at url: URL) throws -> (removed: Int, failed: [URL])
```

- 递归遍历所有条目（含符号链接本身，不跟随）
- 对每个路径调用 `removexattr(path, "com.apple.quarantine", 0)`
- `ENOATTR` 视为成功
- 其他错误收集到 `failed`，不中断

### 5.7 FileAssociation

```swift
enum FileAssociationService {
    static var isDefaultForDiskImages: Bool { get }
    static func setAsDefault() throws
    static func restoreSystemDefault() throws
}
```

- 优先设置 `com.apple.disk-image-udif`（dmg 实际 UTI），随后设置 `public.disk-image`（父类型）
- `LSSetDefaultRoleHandlerForContentType(uti, .all, bundleID)`
- 查询用 `LSCopyDefaultRoleHandlerForContentType`
- 失败抛错并在 UI 展示系统原话

Info.plist 中声明：

```xml
<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key><string>Disk Image</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Owner</string>
    <key>LSItemContentTypes</key>
    <array><string>public.disk-image</string><string>com.apple.disk-image-udif</string></array>
  </dict>
</array>
```

### 5.8 LaunchServicesRegistrar

`lsregister` 是私有工具，路径随系统版本变化。实现顺序：

1. `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` 不适用
2. 直接调用 `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f <path>`
3. 找不到工具则跳过（不视为失败）

## 6. UI 设计

### 6.1 窗口

| 属性 | 值 |
|---|---|
| styleMask | `[.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]` |
| titleVisibility | `.hidden` |
| titlebarAppearsTransparent | `true` |
| isOpaque | `false` |
| backgroundColor | `.clear` |
| isMovableByWindowBackground | `true` |
| 材质 | `NSVisualEffectView`，`material = .hudWindow`，`blendingMode = .behindWindow`，`state = .followsWindowActiveState` |
| 圆角 | 内容容器 `cornerRadius = 14`，`masksToBounds = true`；阴影保持 `window.hasShadow = true` |

SwiftUI 侧通过 `NSViewRepresentable` 包装 `NSVisualEffectView`，作为根背景；窗口配置在 `RootWindow` 的 `.onAppear` 里对 `NSApp.keyWindow` 应用。

### 6.2 布局

```
┌──────────────────────────────────────────┐
│  [<] [^]   multiChat 1.4.7.dmg     [⚙]   │  导航条（毛玻璃胶囊）
├──────────────────────────────────────────┤
│                                          │
│         内容区（DMG 背景图 + 图标）       │
│                                          │
├──────────────────────────────────────────┤
│  已隐藏 2 项        [⚡ 安装应用]  [⏏]     │  底部栏（毛玻璃胶囊）
└──────────────────────────────────────────┘
```

### 6.3 内容区双模式

| 模式 | 触发 | 绘制 |
|---|---|---|
| 布局模式 | 根目录，且解析出背景图或至少一个 `iconPositions` | `ZStack`：背景图（1:1 原尺寸、左上角固定、不拉伸）+ 有坐标的条目用 `.position()` 绝对定位，无坐标的条目按网格排布在下方 |
| 网格模式 | 子目录，或解析失败 | `LazyVGrid`，自适应列宽，最小单元 96pt |

背景图绘制规则（与 Finder 一致）：以原生像素尺寸从内容区左上角开始绘制，窗口放大时右侧/底部露出 `backgroundColor` 或透明，**绝不缩放**。

### 6.4 图标

- 统一用 `NSWorkspace.shared.icon(forFile:)`，天然带系统对 `.app` 的圆角与现代图标处理
- 图标点击无反应；双击：`.app` 触发安装确认、文件夹进入、文件用 `NSWorkspace.open` 打开
- 支持拖拽导出：`.onDrag { NSItemProvider(contentsOf: url) }`，可把 `.app` 直接拖到 Finder 的 /Applications

### 6.5 首启关联弹窗

`AssociationSheet`，同一个毛玻璃窗口内以 sheet 呈现：

- 标题「关联文件格式」
- 列表一行：系统磁盘映像图标 + `DMG 磁盘映像` + `.dmg` + 勾选框（默认勾选）
- 说明文字：「勾选后，双击 .dmg 文件将由 AZip 打开」
- 按钮：`以后再说` / `确认关联`
- `UserDefaults` 键 `didOfferFileAssociation` 记录是否已询问
- 设置页（`⌘,`）可重新打开该 sheet，并提供「恢复系统默认」

### 6.6 交互与快捷键

| 操作 | 快捷键 |
|---|---|
| 打开 dmg | `⌘O` |
| 安装应用 | `⌘⇧I` |
| 返回 / 上级 | `⌘[` / `⌘↑` |
| 卸载并关闭 | `⌘W`（先 detach） |

窗口关闭时必须 detach：`windowWillClose` → 异步 detach，不阻塞关闭。

### 6.7 状态机

```swift
enum SessionState: Sendable {
    case idle
    case mounting
    case browsing(MountResult, [VolumeEntry], DMGWindowLayout?)
    case installing(app: URL, progress: Double)
    case failed(String)
    case unmounted
}
```

## 7. 关键流程

### 7.1 双击 dmg

```
Finder 双击
  → LaunchServices 启动 AZip（若未运行）
  → application(_:open:) 收到 URL
  → hdiutil attach（后台）
  → 扫描根目录
  → 读 .DS_Store → DMGWindowLayout
  → 窗口尺寸调整为 contentSize
  → 显示
```

### 7.2 一键安装

```
点「安装应用」
  → 选择目标 app（唯一 .app 则直接选，多个则弹选择）
  → 冲突检查
      ├─ 无冲突 → 进入拷贝
      └─ 有冲突 → InstallConflictSheet
                    ├─ 取消 → 结束
                    └─ 覆盖 → 进入拷贝
  → ditto 到 staging（进度环）
  → 备份旧版（如覆盖）
  → staging → 最终路径
  → 清 quarantine
  → lsregister
  → 成功提示（含「在访达中显示」）
  → 自动 detach
  → 窗口回到 idle
```

### 7.3 关闭窗口

```
windowWillClose
  → detach（force 兜底）
  → 清理临时 staging / backup 残留（仅 app 自己创建的）
```

## 8. 错误处理与降级

| 错误 | 用户可见文案 | 降级 |
|---|---|---|
| dmg 挂载失败（损坏） | 「无法打开该磁盘映像，文件可能已损坏」+ 原始 stderr | 无 |
| 挂载超时 | 「挂载超时，已取消」 | 自动 detach |
| 无 `.DS_Store` | 无提示 | 网格模式 |
| 背景图找不到 | 无提示 | 用 `backgroundColor` 或透明 |
| alias 解析失败 | 无提示 | 扫描 `.background` 目录 |
| `/Applications` 不可写 | 「没有权限写入应用程序文件夹」 | 提供「在访达中打开」引导手动拖拽 |
| 拷贝失败 | 「安装失败」+ 简要原因 | 回滚旧版 |
| 清隔离失败 | 「已安装，但未能移除隔离属性，首次打开可能需要右键选择打开」 | 不回滚 |
| 卸载卷失败 | 静默记录日志，窗口照常关闭 | 无（不自动清理任何 `/Volumes` 挂载点，避免误伤） |

## 9. 安全边界（不可协商）

| 规则 | 说明 |
|---|---|
| 绝不删除用户文件 | 唯一例外：用户明确确认覆盖安装时，旧版 `NSWorkspace.recycle` 进废纸篓（可恢复） |
| 不改动原 dmg | 挂载参数固定 `-readonly` |
| 不跟随符号链接写文件 | `QuarantineCleaner` 只改链接自身的 xattr |
| 不信任 dmg 内路径 | 背景图别名只取文件名，强制拼接在当前挂载点下 |
| 不自作主张提权 | 首期无 admin 提权，权限不足只报错与引导 |
| 只在自身目录内建临时文件 | staging/backup 前缀统一 `.azip-`，且只在 `/Applications` 与本 app 的 `Caches` 内 |

## 10. 测试策略

| 层级 | 内容 |
|---|---|
| 单元 | `DSStoreReader`（真实 fixture：带背景、无背景、带图标坐标三类）、hdiutil plist 解析、坐标换算、`VolumeEntry` 过滤规则、`AppInstaller` 全部失败路径（用临时目录 + 假 `.app`）、`QuarantineCleaner`（自建带 xattr 文件） |
| 集成 | `Scripts/integration_test.sh`：`hdiutil create` 生成含假 `.app` 的 dmg → 挂载 → 安装到临时目录 → 断言文件存在且无 quarantine → 卸载 → 断言卷消失 |
| 手动 | 用 2～3 个真实带背景 dmg（如微信、Chrome 风格），与 Finder 打开结果逐项比对背景图位置与图标落点 |

### 测试数据

`Fixtures/dsstore/` 中的 `.DS_Store` 从公开的 DMG（如 [create-dmg](https://github.com/create-dmg/create-dmg) 生成物）中提取，并附来源说明文件。**不做任何数据删除操作**，测试产物全部落在临时目录。

## 11. 构建与签名

```bash
# Scripts/build.sh
xcodegen generate
xcodebuild -project AZip.xcodeproj -scheme AZip -configuration Debug build
```

| 项 | 值 |
|---|---|
| Bundle ID | `com.dengpeng.AZip` |
| Signing | 本地自签 `AZip Local Code Signing`（若钥匙串中暂无，出现构建报错时由用户在「钥匙串访问」手动创建一张 Code Signing 证书，或临时降级为 ad-hoc `-`） |
| Entitlements | 空（无沙盒、无 hardened runtime） |
| Deployment Target | macOS 14.0 |

## 12. 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| `Iloc` 坐标换算系数判断错误 | 图标位置偏移，背景箭头对不上 | 用真实 fixture 反推并单测锁定；实现阶段先做一次实测 |
| 不同 macOS 版本 `.DS_Store` 字段差异 | 部分 dmg 只还原背景、不还原图标 | 逐字段降级；缺字段时用网格布局 |
| `hdiutil` 在 macOS 27 上行为变化 | 挂载失败 | 保留原始 stderr；必要时改用 DiskArbitration |
| 接管 `.dmg` 后系统「磁盘工具」行为受影响 | 用户无法再用系统默认方式打开 | 设置页提供「恢复系统默认」一键回退 |
| 本地自签导致 TCC 授权重置 | 无（本 app 不需要 TCC 权限） | 不重要 |
| 覆盖安装中途崩溃 | 旧版留在 `.azip-backup-*` | 启动时扫描 `/Applications/.azip-backup-*`，提示用户位置；不自动删除、不自动改名 |

## 13. 后续（不在本期）

- 压缩 / 解压（zip、tar、7z、rar）
- `.dmg` 创建
- Developer ID 签名 + 公证
- 应用解包/提取 DMG 内单个文件
