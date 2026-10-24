# AZip DMG 关联与一键安装 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现一个 macOS 应用：接管 `.dmg` 文件，挂载后按原生布局展示内容，并提供一键把 `.app` 安装到 `/Applications` 且移除隔离属性的能力。

**Architecture:** 拆成两个 target：`AZipCore`（纯逻辑 framework，无 UI，全部可单测）与 `AZip`（SwiftUI 应用，只做状态与呈现）。Core 通过 `ProcessRunner` 调 `hdiutil` / `ditto` 完成挂载与拷贝，自带 Bud1 格式的 `.DS_Store` 解析器还原背景与图标坐标。

**Tech Stack:** Swift 6、SwiftUI、AppKit 桥接、XcodeGen、XCTest、`hdiutil`、`ditto`。

## Global Constraints

- Deployment target：`macOS 14.0`
- Swift 语言模式：`Swift 6`（`SWIFT_VERSION = 6.0`）
- 不引入任何第三方依赖
- **不启用 App Sandbox**，entitlements 为空，`ENABLE_HARDENED_RUNTIME = NO`
- Bundle ID：`com.dengpeng.AZip`（app）、`com.dengpeng.AZipCore`（framework）
- 签名：ad-hoc `CODE_SIGN_IDENTITY = "-"`
- Core 层所有对外类型 `public` 且 `Sendable`；UI 层 `@MainActor`
- UI 文案全部中文
- **任何代码路径都不得删除用户文件**；唯一例外是用户确认覆盖安装时把旧 app 交给 `NSWorkspace.recycle`（移入废纸篓）
- 测试命令统一为：
  ```bash
  xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet
  ```

---

## File Structure

| 文件 | 职责 |
|---|---|
| `project.yml` | XcodeGen 工程定义：`AZipCore`、`AZip`、`AZipCoreTests` 三个 target |
| `Sources/AZipCore/ProcessRunner.swift` | 子进程执行统一封装（超时、输出捕获） |
| `Sources/AZipCore/DiskImageMounter.swift` | `hdiutil attach/detach` + plist 解析 |
| `Sources/AZipCore/DSStoreReader.swift` | Bud1 二进制解析，产出 `DSStoreDocument` |
| `Sources/AZipCore/DMGWindowLayout.swift` | 背景图定位、坐标换算，产出 `DMGWindowLayout` |
| `Sources/AZipCore/VolumeEntry.swift` | 条目模型 + 目录扫描与过滤 |
| `Sources/AZipCore/QuarantineCleaner.swift` | 递归移除 `com.apple.quarantine` |
| `Sources/AZipCore/AppInstaller.swift` | 拷贝、冲突、备份、回滚、进度 |
| `Sources/AZipCore/FileAssociation.swift` | `.dmg` 默认打开方式读写 |
| `Sources/AZipCore/LaunchServicesRegistrar.swift` | `lsregister -f` 调用（失败不致命） |
| `Sources/AZipApp/AZipApp.swift` | `@main`、`WindowGroup` |
| `Sources/AZipApp/AppDelegate.swift` | 接收 Finder 传来的 dmg URL |
| `Sources/AZipApp/DMGSessionModel.swift` | `@MainActor` 状态机 |
| `Sources/AZipApp/Views/RootWindow.swift` | 毛玻璃容器 + 窗口配置 |
| `Sources/AZipApp/Views/VisualEffectBackground.swift` | `NSVisualEffectView` 包装 |
| `Sources/AZipApp/Views/WindowConfigurator.swift` | `NSWindow` 属性注入 |
| `Sources/AZipApp/Views/NavigationBar.swift` | 返回 / 上级 / 路径 |
| `Sources/AZipApp/Views/LayoutContentView.swift` | 有 `.DS_Store` 布局时的绝对定位视图 |
| `Sources/AZipApp/Views/GridContentView.swift` | 网格视图 |
| `Sources/AZipApp/Views/FileTile.swift` | 单条目视图 |
| `Sources/AZipApp/Views/BottomBar.swift` | 安装按钮 + 进度 |
| `Sources/AZipApp/Views/AssociationSheet.swift` | 首启关联弹窗 |
| `Sources/AZipApp/Views/InstallTargetSheet.swift` | 多个 `.app` 时的选择 |
| `Sources/AZipApp/Views/InstallConflictSheet.swift` | 同名覆盖确认 |
| `Tests/AZipCoreTests/*.swift` | 单测 |
| `Tests/AZipCoreTests/Support/DSStoreFixtureBuilder.swift` | 构造测试用 `.DS_Store` 字节 |
| `Scripts/build.sh` | `xcodegen generate` + `xcodebuild` |
| `Scripts/make_test_dmg.sh` | 生成测试 dmg |
| `Scripts/integration_test.sh` | 全链路集成测试 |

---

## Task 1: 工程骨架

**Files:**
- Create: `project.yml`
- Create: `Sources/AZipCore/Placeholder.swift`
- Create: `Sources/AZipApp/AZipApp.swift`
- Create: `Sources/AZipApp/AppDelegate.swift`
- Create: `Tests/AZipCoreTests/SmokeTests.swift`
- Create: `Scripts/build.sh`
- Create: `.gitignore`（已存在则确认内容）

**Interfaces:**
- Consumes: 无
- Produces: 可构建可测试的工程；`AZipCore` framework target 名；scheme 名 `AZip`

- [ ] **Step 1: 写 `project.yml`**

```yaml
name: AZip
options:
  bundleIdPrefix: com.dengpeng
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGNING_REQUIRED: YES
    CODE_SIGNING_ALLOWED: YES
    ENABLE_HARDENED_RUNTIME: NO
    ENABLE_USER_SCRIPT_SANDBOXING: NO

targets:
  AZipCore:
    type: framework
    platform: macOS
    sources:
      - path: Sources/AZipCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.dengpeng.AZipCore
        SKIP_INSTALL: YES
        DEFINES_MODULE: YES
        GENERATE_INFOPLIST_FILE: YES

  AZip:
    type: application
    platform: macOS
    sources:
      - path: Sources/AZipApp
    dependencies:
      - target: AZipCore
    info:
      path: Resources/Info.plist
      properties:
        CFBundleName: AZip
        CFBundleDisplayName: AZip
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        LSMinimumSystemVersion: "14.0"
        NSHumanReadableCopyright: ""
        LSApplicationCategoryType: public.app-category.utilities
        CFBundleDocumentTypes:
          - CFBundleTypeName: Disk Image
            CFBundleTypeRole: Viewer
            LSHandlerRank: Owner
            LSItemContentTypes:
              - public.disk-image
              - com.apple.disk-image-udif
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.dengpeng.AZip
        GENERATE_INFOPLIST_FILE: NO

  AZipCoreTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests/AZipCoreTests
    dependencies:
      - target: AZipCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.dengpeng.AZipCoreTests
        GENERATE_INFOPLIST_FILE: YES

schemes:
  AZip:
    build:
      targets:
        AZip: all
        AZipCore: all
        AZipCoreTests: [test]
    test:
      targets:
        - AZipCoreTests
    run:
      config: Debug
```

- [ ] **Step 2: 写最小 Core 占位与测试**

`Sources/AZipCore/Placeholder.swift`:

```swift
import Foundation

public enum AZipCoreVersion {
    public static let current = "0.1.0"
}
```

`Tests/AZipCoreTests/SmokeTests.swift`:

```swift
import XCTest
@testable import AZipCore

final class SmokeTests: XCTestCase {
    func testCoreLoads() {
        XCTAssertEqual(AZipCoreVersion.current, "0.1.0")
    }
}
```

- [ ] **Step 3: 写最小 App 入口**

`Sources/AZipApp/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
```

`Sources/AZipApp/AZipApp.swift`:

```swift
import SwiftUI

@main
struct AZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("AZip") {
            Text("AZip")
                .frame(minWidth: 480, minHeight: 320)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
```

- [ ] **Step 4: 写构建脚本**

`Scripts/build.sh`:

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project AZip.xcodeproj -scheme AZip -configuration Debug build -quiet
```

```bash
chmod +x Scripts/build.sh
```

- [ ] **Step 5: 构建并运行测试**

Run:
```bash
cd <repo-root> && ./Scripts/build.sh && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet
```

Expected: `BUILD SUCCEEDED`，测试 `SmokeTests.testCoreLoads` 通过。

- [ ] **Step 6: Commit**

```bash
git add project.yml Sources Tests Scripts .gitignore
git commit -m "chore: 搭建 AZip 工程骨架"
```

---

## Task 2: ProcessRunner

**Files:**
- Create: `Sources/AZipCore/ProcessRunner.swift`
- Test: `Tests/AZipCoreTests/ProcessRunnerTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `ProcessRunner.run(_ executable: String, _ arguments: [String], timeoutSeconds: Double) async throws -> ProcessRunner.Result`
  - `ProcessRunner.Result { status: Int32, stdout: String, stderr: String }`
  - `ProcessRunnerError { launchFailed(String), timedOut }`

- [ ] **Step 1: 写失败测试**

`Tests/AZipCoreTests/ProcessRunnerTests.swift`:

```swift
import XCTest
@testable import AZipCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesStdout() async throws {
        let result = try await ProcessRunner.run("/bin/echo", ["hello"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testCapturesStderrAndStatus() async throws {
        let result = try await ProcessRunner.run("/bin/sh", ["-c", "echo boom >&2; exit 3"])
        XCTAssertEqual(result.status, 3)
        XCTAssertTrue(result.stderr.contains("boom"))
    }

    func testTimesOut() async throws {
        do {
            _ = try await ProcessRunner.run("/bin/sleep", ["5"], timeoutSeconds: 0.3)
            XCTFail("应当超时")
        } catch let error as ProcessRunnerError {
            guard case .timedOut = error else {
                return XCTFail("错误类型不符：\(error)")
            }
        }
    }

    func testLaunchFailure() async throws {
        do {
            _ = try await ProcessRunner.run("/nonexistent/binary", [])
            XCTFail("应当抛错")
        } catch let error as ProcessRunnerError {
            guard case .launchFailed = error else {
                return XCTFail("错误类型不符：\(error)")
            }
        }
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:
```bash
cd <repo-root> && xcodegen generate >/dev/null && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -20
```
Expected: 编译失败，提示 `cannot find 'ProcessRunner' in scope`。

- [ ] **Step 3: 实现 ProcessRunner**

`Sources/AZipCore/ProcessRunner.swift`:

```swift
import Foundation

public enum ProcessRunnerError: Error, Sendable, Equatable {
    case launchFailed(String)
    case timedOut
}

public enum ProcessRunner {
    public struct Result: Sendable {
        public let status: Int32
        public let stdout: String
        public let stderr: String

        public init(status: Int32, stdout: String, stderr: String) {
            self.status = status
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    public static func run(
        _ executable: String,
        _ arguments: [String],
        timeoutSeconds: Double = 60
    ) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        let outTask = Task.detached(priority: .userInitiated) {
            outHandle.readDataToEndOfFile()
        }
        let errTask = Task.detached(priority: .userInitiated) {
            errHandle.readDataToEndOfFile()
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                _ = await outTask.value
                _ = await errTask.value
                throw ProcessRunnerError.timedOut
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        let outData = await outTask.value
        let errData = await errTask.value

        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run:
```bash
cd <repo-root> && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -20
```
Expected: 4 个 `ProcessRunnerTests` 全部通过。

- [ ] **Step 5: Commit**

```bash
git add Sources/AZipCore/ProcessRunner.swift Tests/AZipCoreTests/ProcessRunnerTests.swift
git commit -m "feat(core): 添加带超时的子进程执行器"
```

---

## Task 3: DiskImageMounter

**Files:**
- Create: `Sources/AZipCore/DiskImageMounter.swift`
- Test: `Tests/AZipCoreTests/DiskImageMounterTests.swift`
- Test fixture: `Tests/AZipCoreTests/Fixtures/attach_plist.txt`

**Interfaces:**
- Consumes: `ProcessRunner.run(_:_:timeoutSeconds:)`
- Produces:
  - `MountResult { mountPoint: URL, deviceEntry: String, volumeName: String }`（`Sendable`）
  - `DiskImageMounter.attach(_ dmgURL: URL) async throws -> MountResult`
  - `DiskImageMounter.detach(_ result: MountResult) async throws`
  - `DiskImageMounter.parseAttachOutput(_ data: Data) throws -> MountResult`
  - `MountError { toolFailed(code: Int32, message: String), noMountPointFound }`

- [ ] **Step 1: 写 fixture**

`Tests/AZipCoreTests/Fixtures/attach_plist.txt`（把 XML 原样保存；XcodeGen 会把 `Tests` 目录整体加入测试 target，需要保证非源码文件被当作资源）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>system-entities</key>
	<array>
		<dict>
			<key>content-hint</key>
			<string>GUID_partition_scheme</string>
			<key>dev-entry</key>
			<string>/dev/disk9</string>
			<key>potentially-mountable</key>
			<false/>
		</dict>
		<dict>
			<key>content-hint</key>
			<string>Apple_HFS</string>
			<key>dev-entry</key>
			<string>/dev/disk9s1</string>
			<key>mount-point</key>
			<string>/Volumes/TestApp</string>
			<key>potentially-mountable</key>
			<true/>
			<key>volume-kind</key>
			<string>hfs</string>
			<key>volume-name</key>
			<string>TestApp</string>
		</dict>
	</array>
</dict>
</plist>
```

把 `project.yml` 中的 `AZipCoreTests` target 整块替换为（新增了 `excludes` 与 `resources`，让 fixture 作为 bundle 资源被测试读取）：

```yaml
  AZipCoreTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests/AZipCoreTests
        excludes:
          - "Fixtures/**"
    resources:
      - path: Tests/AZipCoreTests/Fixtures
    dependencies:
      - target: AZipCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.dengpeng.AZipCoreTests
        GENERATE_INFOPLIST_FILE: YES
```

- [ ] **Step 2: 写失败测试**

`Tests/AZipCoreTests/DiskImageMounterTests.swift`:

```swift
import XCTest
@testable import AZipCore

final class DiskImageMounterTests: XCTestCase {
    func testParsesMountPointFromFixture() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "attach_plist", withExtension: "txt"))
        let data = try Data(contentsOf: url)
        let result = try DiskImageMounter.parseAttachOutput(data)
        XCTAssertEqual(result.mountPoint.path, "/Volumes/TestApp")
        XCTAssertEqual(result.deviceEntry, "/dev/disk9s1")
        XCTAssertEqual(result.volumeName, "TestApp")
    }

    func testParsesPlistWithoutMountPoint() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict><key>system-entities</key><array>
        <dict><key>dev-entry</key><string>/dev/disk9</string></dict>
        </array></dict>
        </plist>
        """
        XCTAssertThrowsError(try DiskImageMounter.parseAttachOutput(Data(xml.utf8))) { error in
            guard case MountError.noMountPointFound = error else {
                return XCTFail("错误类型不符：\(error)")
            }
        }
    }
}
```

- [ ] **Step 3: 运行测试确认失败**

Run:
```bash
cd <repo-root> && xcodegen generate >/dev/null && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -20
```
Expected: 编译失败，提示 `cannot find 'DiskImageMounter' in scope`。

- [ ] **Step 4: 实现 DiskImageMounter**

`Sources/AZipCore/DiskImageMounter.swift`:

```swift
import Foundation

public struct MountResult: Sendable, Equatable {
    public let mountPoint: URL
    public let deviceEntry: String
    public let volumeName: String

    public init(mountPoint: URL, deviceEntry: String, volumeName: String) {
        self.mountPoint = mountPoint
        self.deviceEntry = deviceEntry
        self.volumeName = volumeName
    }
}

public enum MountError: Error, Sendable {
    case toolFailed(code: Int32, message: String)
    case noMountPointFound
}

public enum DiskImageMounter {
    private static let hdiutil = "/usr/bin/hdiutil"

    public static func attach(_ dmgURL: URL) async throws -> MountResult {
        let result = try await ProcessRunner.run(
            hdiutil,
            ["attach", dmgURL.path, "-plist", "-nobrowse", "-noautoopen", "-readonly"],
            timeoutSeconds: 120
        )
        guard result.status == 0 else {
            throw MountError.toolFailed(code: result.status, message: result.stderr)
        }
        return try parseAttachOutput(Data(result.stdout.utf8))
    }

    public static func detach(_ result: MountResult) async throws {
        let plain = try await ProcessRunner.run(
            hdiutil, ["detach", result.deviceEntry], timeoutSeconds: 30
        )
        if plain.status == 0 { return }

        let forced = try await ProcessRunner.run(
            hdiutil, ["detach", result.deviceEntry, "-force"], timeoutSeconds: 30
        )
        if forced.status != 0 {
            throw MountError.toolFailed(code: forced.status, message: forced.stderr)
        }
    }

    public static func parseAttachOutput(_ data: Data) throws -> MountResult {
        guard
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let entities = plist["system-entities"] as? [[String: Any]]
        else {
            throw MountError.noMountPointFound
        }

        for entity in entities {
            guard
                let mountPoint = entity["mount-point"] as? String,
                let deviceEntry = entity["dev-entry"] as? String
            else { continue }
            let volumeName = (entity["volume-name"] as? String)
                ?? URL(fileURLWithPath: mountPoint).lastPathComponent
            return MountResult(
                mountPoint: URL(fileURLWithPath: mountPoint),
                deviceEntry: deviceEntry,
                volumeName: volumeName
            )
        }
        throw MountError.noMountPointFound
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

Run:
```bash
cd <repo-root> && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -20
```
Expected: `DiskImageMounterTests` 两个用例通过。

- [ ] **Step 6: Commit**

```bash
git add project.yml Sources/AZipCore/DiskImageMounter.swift Tests/AZipCoreTests/Fixtures Tests/AZipCoreTests/DiskImageMounterTests.swift
git commit -m "feat(core): 添加 hdiutil 挂载与卸载"
```

---

## Task 4: DSStoreReader

**Files:**
- Create: `Sources/AZipCore/DSStoreReader.swift`
- Create: `Tests/AZipCoreTests/Support/DSStoreFixtureBuilder.swift`
- Test: `Tests/AZipCoreTests/DSStoreReaderTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `DSStoreDocument { windowFrame: CGRect?, iconSize: CGFloat?, textSize: CGFloat?, backgroundColor: [CGFloat]?, backgroundAlias: Data?, iconPositions: [String: CGPoint] }`（`Sendable`，全部 `public var`）
  - `DSStoreReader.parse(_ data: Data) -> DSStoreDocument`
  - `DSStoreReader.pointsPerLocationUnit: CGFloat = 1.0 / 1000.0`（实测校准常量）

- [ ] **Step 1: 写 fixture 构造器**

`Tests/AZipCoreTests/Support/DSStoreFixtureBuilder.swift`:

```swift
import Foundation

/// 构造最小可解析的 Bud1 文件，用于单测。
struct DSStoreFixtureBuilder {
    private var records: [(name: String, code: String, type: String, value: Data)] = []

    mutating func addICVP(iconSize: Double, textSize: Double, backgroundColor: [UInt8]?) {
        var payload = Data()
        payload.append(field(code: "iconSize", type: "doub", value: doubleData(iconSize)))
        payload.append(field(code: "textSize", type: "doub", value: doubleData(textSize)))
        if let backgroundColor {
            payload.append(field(code: "backgroundColor", type: "blob", value: Data(backgroundColor)))
        }
        records.append((name: ".", code: "icvp", type: "blob", value: payload))
    }

    mutating func addBWSP(width: Double, height: Double) {
        let bounds = "{64, 64}, {\(Int(width)), \(Int(height))}"
        var payload = Data()
        payload.append(field(code: "WindowBounds", type: "type", value: utf16beData(bounds)))
        records.append((name: ".", code: "bwsp", type: "blob", value: payload))
    }

    mutating func addIcon(name: String, x: Int, y: Int) {
        var value = Data()
        value.append(beUInt32(UInt32(x)))
        value.append(beUInt32(UInt32(y)))
        records.append((name: name, code: "Iloc", type: "blob", value: value))
    }

    func build() -> Data {
        var block = Data()
        block.append(beUInt32(0)) // next block offset = 0
        for record in records {
            let nameData = utf16beData(record.name)
            block.append(beUInt32(UInt32(nameData.count / 2)))
            block.append(nameData)
            block.append(Data(record.code.utf8))
            block.append(Data(record.type.utf8))
            block.append(beUInt32(UInt32(record.value.count)))
            block.append(record.value)
        }
        block.append(beUInt32(0)) // 结束标记：filename length == 0

        let rootOffset = 0x1000
        var data = Data("Bud1".utf8)
        data.append(beUInt32(UInt32(rootOffset)))
        data.append(Data(count: 256)) // block 索引表留空
        if data.count < rootOffset {
            data.append(Data(count: rootOffset - data.count))
        }
        data.append(block)
        return data
    }

    // MARK: - Helpers

    private func field(code: String, type: String, value: Data) -> Data {
        var data = Data()
        data.append(Data(code.utf8))
        data.append(Data(type.utf8))
        data.append(beUInt32(UInt32(value.count)))
        data.append(value)
        return data
    }

    private func beUInt32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private func doubleData(_ value: Double) -> Data {
        withUnsafeBytes(of: value.bitPattern.bigEndian) { Data($0) }
    }

    private func utf16beData(_ string: String) -> Data {
        var data = Data()
        for unit in string.utf16 {
            data.append(UInt8(unit >> 8))
            data.append(UInt8(unit & 0xFF))
        }
        return data
    }
}
```

- [ ] **Step 2: 写失败测试**

`Tests/AZipCoreTests/DSStoreReaderTests.swift`:

```swift
import XCTest
@testable import AZipCore

final class DSStoreReaderTests: XCTestCase {
    func testParsesIconPositions() {
        var builder = DSStoreFixtureBuilder()
        builder.addIcon(name: "MultiChat.app", x: 120_000, y: 140_000)
        builder.addIcon(name: "Applications", x: 320_000, y: 140_000)

        let doc = DSStoreReader.parse(builder.build())

        XCTAssertEqual(doc.iconPositions.count, 2)
        let app = doc.iconPositions["MultiChat.app"]
        XCTAssertEqual(app?.x ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(app?.y ?? 0, 140, accuracy: 0.001)
        XCTAssertEqual(doc.iconPositions["Applications"]?.x ?? 0, 320, accuracy: 0.001)
    }

    func testParsesWindowProperties() {
        var builder = DSStoreFixtureBuilder()
        builder.addBWSP(width: 640, height: 400)
        builder.addICVP(
            iconSize: 80,
            textSize: 12,
            backgroundColor: Array(repeating: 255, count: 12)
        )

        let doc = DSStoreReader.parse(builder.build())

        XCTAssertEqual(doc.windowFrame?.size.width ?? 0, 640, accuracy: 0.001)
        XCTAssertEqual(doc.windowFrame?.size.height ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(doc.iconSize ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(doc.textSize ?? 0, 12, accuracy: 0.001)
        XCTAssertEqual(doc.backgroundColor?.count, 6)
        XCTAssertEqual(doc.backgroundColor?[0] ?? 0, 1.0, accuracy: 0.001)
    }

    func testRejectsNonBud1Data() {
        let doc = DSStoreReader.parse(Data("not a ds_store".utf8))
        XCTAssertTrue(doc.iconPositions.isEmpty)
        XCTAssertNil(doc.windowFrame)
    }

    func testIgnoresTruncatedRecords() {
        var builder = DSStoreFixtureBuilder()
        builder.addIcon(name: "A.app", x: 10_000, y: 20_000)
        var data = builder.build()
        data = data.prefix(data.count - 4)

        let doc = DSStoreReader.parse(data)
        XCTAssertTrue(doc.iconPositions.isEmpty || doc.iconPositions["A.app"] != nil)
    }
}
```

- [ ] **Step 3: 运行测试确认失败**

Run:
```bash
cd <repo-root> && xcodegen generate >/dev/null && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -20
```
Expected: 编译失败，提示 `cannot find 'DSStoreReader' in scope`。

- [ ] **Step 4: 实现 DSStoreReader**

`Sources/AZipCore/DSStoreReader.swift`:

```swift
import CoreGraphics
import Foundation

public struct DSStoreDocument: Sendable {
    public var windowFrame: CGRect?
    public var iconSize: CGFloat?
    public var textSize: CGFloat?
    public var backgroundColor: [CGFloat]?
    public var backgroundAlias: Data?
    public var iconPositions: [String: CGPoint] = [:]

    public init() {}
}

public enum DSStoreReader {
    /// `.DS_Store` 中 `Iloc` 坐标的换算系数。
    ///
    /// Finder 以千分之一为单位存储图标位置；若实测发现某些系统版本直接存点值，
    /// 调整此常量即可，单测会跟着校准。
    public static let pointsPerLocationUnit: CGFloat = 1.0 / 1000.0

    public static func parse(_ data: Data) -> DSStoreDocument {
        var document = DSStoreDocument()
        guard data.count >= 8, data.prefix(4) == Data("Bud1".utf8) else {
            return document
        }

        let rootOffset = Int(readUInt32(data, at: 4))
        guard rootOffset > 0, rootOffset < data.count else { return document }

        var visited = Set<Int>()
        var queue = [rootOffset]

        while let offset = queue.popLast() {
            guard offset > 0, offset + 4 <= data.count, visited.insert(offset).inserted else {
                continue
            }
            let next = Int(readUInt32(data, at: offset))
            if next > 0, next < data.count, !visited.contains(next) {
                queue.append(next)
            }
            parseBlock(data, at: offset + 4, into: &document)
        }

        return document
    }

    // MARK: - Block parsing

    private static func parseBlock(_ data: Data, at start: Int, into document: inout DSStoreDocument) {
        var cursor = start

        while cursor + 4 <= data.count {
            let nameLength = Int(readUInt32(data, at: cursor))
            cursor += 4
            if nameLength == 0 { break }

            let nameBytes = nameLength * 2
            guard cursor + nameBytes + 12 <= data.count else { break }
            let name = String(
                data: data[cursor..<cursor + nameBytes],
                encoding: .utf16BigEndian
            ) ?? ""
            cursor += nameBytes

            let code = String(data: data[cursor..<cursor + 4], encoding: .ascii) ?? ""
            cursor += 4
            let type = String(data: data[cursor..<cursor + 4], encoding: .ascii) ?? ""
            cursor += 4
            let valueLength = Int(readUInt32(data, at: cursor))
            cursor += 4

            guard valueLength >= 0, cursor + valueLength <= data.count else { break }
            let value = data[cursor..<cursor + valueLength]
            cursor += valueLength

            apply(code: code, type: type, name: name, value: Data(value), into: &document)
        }
    }

    private static func apply(
        code: String,
        type: String,
        name: String,
        value: Data,
        into document: inout DSStoreDocument
    ) {
        switch code {
        case "Iloc":
            guard value.count >= 8 else { return }
            let x = CGFloat(readUInt32(value, at: 0)) * pointsPerLocationUnit
            let y = CGFloat(readUInt32(value, at: 4)) * pointsPerLocationUnit
            document.iconPositions[name] = CGPoint(x: x, y: y)

        case "icvp":
            parseFields(value) { fieldCode, fieldType, fieldValue in
                switch fieldCode {
                case "iconSize":
                    document.iconSize = readDouble(fieldValue, type: fieldType)
                case "textSize":
                    document.textSize = readDouble(fieldValue, type: fieldType)
                case "backgroundColor":
                    document.backgroundColor = readColor(fieldValue)
                case "backgroundImageAlias":
                    document.backgroundAlias = fieldValue
                default:
                    break
                }
            }

        case "bwsp":
            parseFields(value) { fieldCode, fieldType, fieldValue in
                guard fieldCode == "WindowBounds" else { return }
                if let frame = readWindowBounds(fieldValue, type: fieldType) {
                    document.windowFrame = frame
                }
            }

        default:
            break
        }
    }

    /// 解析 `icvp` / `bwsp` 内部的 `code(4) + type(4) + length(4) + value` 序列。
    private static func parseFields(
        _ blob: Data,
        _ body: (String, String, Data) -> Void
    ) {
        var cursor = 0
        while cursor + 12 <= blob.count {
            let code = String(data: blob[cursor..<cursor + 4], encoding: .ascii) ?? ""
            cursor += 4
            let type = String(data: blob[cursor..<cursor + 4], encoding: .ascii) ?? ""
            cursor += 4
            let length = Int(readUInt32(blob, at: cursor))
            cursor += 4
            guard length >= 0, cursor + length <= blob.count else { return }
            let value = Data(blob[cursor..<cursor + length])
            cursor += length
            body(code, type, value)
        }
    }

    // MARK: - Value decoding

    private static func readDouble(_ data: Data, type: String) -> CGFloat? {
        switch type {
        case "doub":
            guard data.count >= 8 else { return nil }
            let bits = UInt64(data[0]) << 56 | UInt64(data[1]) << 48
                | UInt64(data[2]) << 40 | UInt64(data[3]) << 32
                | UInt64(data[4]) << 24 | UInt64(data[5]) << 16
                | UInt64(data[6]) << 8 | UInt64(data[7])
            return CGFloat(Double(bitPattern: bits))
        case "shor", "long":
            guard data.count >= 4 else { return nil }
            return CGFloat(Int32(bitPattern: readUInt32(data, at: 0)))
        default:
            return nil
        }
    }

    private static func readColor(_ data: Data) -> [CGFloat]? {
        guard data.count >= 12 else { return nil }
        let components = stride(from: 0, to: 12, by: 2).map { offset -> CGFloat in
            let raw = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            return CGFloat(raw) / 65535.0
        }
        return components
    }

    private static func readWindowBounds(_ data: Data, type: String) -> CGRect? {
        let text: String
        switch type {
        case "type":
            text = String(data: data, encoding: .utf16BigEndian) ?? ""
        case "ustr":
            text = String(data: data, encoding: .macOSRoman) ?? ""
        default:
            return nil
        }
        return parseBoundsString(text)
    }

    private static func parseBoundsString(_ text: String) -> CGRect? {
        let numbers = text
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.-").inverted)
            .compactMap(Double.init)
        guard numbers.count >= 4 else { return nil }
        return CGRect(
            x: numbers[0], y: numbers[1],
            width: numbers[2], height: numbers[3]
        )
    }

    // MARK: - Byte helpers

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

Run:
```bash
cd <repo-root> && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -30
```
Expected: `DSStoreReaderTests` 4 个用例通过。

- [ ] **Step 6: 用真实 dmg 校准坐标系数**

Run:
```bash
hdiutil attach "/path/to/any.dmg" -nobrowse -readonly
xxd "/Volumes/<卷名>/.DS_Store" | head -40
hdiutil detach "/Volumes/<卷名>"
```

预期：观察到 `Iloc` 记录后 8 字节的 x/y 数值量级。若数值是像素的 1000 倍（如 120000 对应 120pt），保持 `pointsPerLocationUnit = 1.0/1000.0`；若数值本身就是像素值，改成 `1.0` 并同步修改 `DSStoreReaderTests.testParsesIconPositions` 的输入为 `120、140`。

- [ ] **Step 7: Commit**

```bash
git add Sources/AZipCore/DSStoreReader.swift Tests/AZipCoreTests/Support Tests/AZipCoreTests/DSStoreReaderTests.swift
git commit -m "feat(core): 解析 .DS_Store 中的窗口属性与图标坐标"
```

---

## Task 5: DMGWindowLayout

**Files:**
- Create: `Sources/AZipCore/DMGWindowLayout.swift`
- Test: `Tests/AZipCoreTests/DMGWindowLayoutTests.swift`

**Interfaces:**
- Consumes: `DSStoreDocument`、`DSStoreReader.pointsPerLocationUnit`
- Produces:
  - `DMGWindowLayout { contentSize: CGSize, backgroundImageURL: URL?, backgroundColor: [CGFloat]?, iconPositions: [String: CGPoint], iconSize: CGFloat }`（`Sendable`）
  - `DMGWindowLayout.make(mountPoint: URL, document: DSStoreDocument) -> DMGWindowLayout?`
  - `DMGWindowLayout.resolveBackgroundImage(mountPoint: URL, document: DSStoreDocument) -> URL?`
  - `DMGWindowLayout.resolveAliasFileName(_ alias: Data) -> String?`

- [ ] **Step 1: 写失败测试**

`Tests/AZipCoreTests/DMGWindowLayoutTests.swift`:

```swift
import XCTest
@testable import AZipCore

final class DMGWindowLayoutTests: XCTestCase {
    private var mountPoint: URL!

    override func setUpWithError() throws {
        mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("AZipLayoutTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: mountPoint.appendingPathComponent(".background"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: mountPoint)
    }

    func testResolvesBackgroundFromDotBackgroundDirectory() throws {
        let image = mountPoint.appendingPathComponent(".background/bg.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)

        let url = DMGWindowLayout.resolveBackgroundImage(
            mountPoint: mountPoint, document: DSStoreDocument()
        )

        XCTAssertEqual(url?.lastPathComponent, "bg.png")
    }

    func testPrefersNamedBackgroundFromAlias() throws {
        let named = mountPoint.appendingPathComponent(".background/brand.png")
        let other = mountPoint.appendingPathComponent(".background/other.png")
        try Data([1]).write(to: named)
        try Data([2]).write(to: other)

        // 直接验证「优先按文件名匹配」这条规则
        let url = DMGWindowLayout.backgroundImage(
            mountPoint: mountPoint, fileName: "brand.png"
        )
        XCTAssertEqual(url?.lastPathComponent, "brand.png")
    }

    func testReturnsNilWhenNoBackgroundExists() {
        XCTAssertNil(
            DMGWindowLayout.resolveBackgroundImage(
                mountPoint: mountPoint, document: DSStoreDocument()
            )
        )
    }

    func testRejectsPathTraversalInAliasFileName() {
        let url = DMGWindowLayout.backgroundImage(
            mountPoint: mountPoint, fileName: "../../etc/passwd"
        )
        XCTAssertNil(url)
        XCTAssertNil(DMGWindowLayout.backgroundImage(mountPoint: mountPoint, fileName: ".."))
    }

    func testMakeReturnsNilWhenNothingToLayout() {
        let document = DSStoreDocument()
        XCTAssertNil(DMGWindowLayout.make(mountPoint: mountPoint, document: document))
    }

    func testMakeUsesWindowSizeAndIconSize() {
        var document = DSStoreDocument()
        document.windowFrame = CGRect(x: 0, y: 0, width: 640, height: 400)
        document.iconSize = 80
        document.iconPositions = ["A.app": CGPoint(x: 120, y: 140)]

        let layout = DMGWindowLayout.make(mountPoint: mountPoint, document: document)

        XCTAssertEqual(layout?.contentSize.width, 640)
        XCTAssertEqual(layout?.contentSize.height, 400)
        XCTAssertEqual(layout?.iconSize, 80)
        XCTAssertEqual(layout?.iconPositions["A.app"]?.x, 120)
    }

    func testMakeClampsIconSizeToReasonableRange() {
        var document = DSStoreDocument()
        document.iconSize = 1000
        document.iconPositions = ["A.app": CGPoint(x: 10, y: 10)]

        XCTAssertEqual(DMGWindowLayout.make(mountPoint: mountPoint, document: document)?.iconSize, 128)
    }

    func testMakeDefaultsWindowSizeWhenMissing() {
        var document = DSStoreDocument()
        document.iconPositions = ["A.app": CGPoint(x: 10, y: 10)]

        let layout = DMGWindowLayout.make(mountPoint: mountPoint, document: document)
        XCTAssertEqual(layout?.contentSize.width, 640)
        XCTAssertEqual(layout?.contentSize.height, 400)
    }
}
```

辅助扩展放在测试文件底部：

```swift
private extension URL {
    func modifyingLastPathComponent(_ name: String) -> URL {
        deletingLastPathComponent().appendingPathComponent(name)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:
```bash
cd <repo-root> && xcodegen generate >/dev/null && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -20
```
Expected: 编译失败，提示 `cannot find 'DMGWindowLayout' in scope`。

- [ ] **Step 3: 实现 DMGWindowLayout**

`Sources/AZipCore/DMGWindowLayout.swift`:

```swift
import CoreGraphics
import Foundation

public struct DMGWindowLayout: Sendable {
    public static let defaultSize = CGSize(width: 640, height: 400)
    public static let minimumSize = CGSize(width: 480, height: 320)
    public static let maximumSize = CGSize(width: 1600, height: 1200)
    public static let defaultIconSize: CGFloat = 64
    public static let minimumIconSize: CGFloat = 48
    public static let maximumIconSize: CGFloat = 128

    public let contentSize: CGSize
    public let backgroundImageURL: URL?
    public let backgroundColor: [CGFloat]?
    public let iconPositions: [String: CGPoint]
    public let iconSize: CGFloat

    public static func make(mountPoint: URL, document: DSStoreDocument) -> DMGWindowLayout? {
        let background = resolveBackgroundImage(mountPoint: mountPoint, document: document)
        guard background != nil || !document.iconPositions.isEmpty else { return nil }

        let rawSize = document.windowFrame?.size ?? defaultSize
        let contentSize = CGSize(
            width: min(max(rawSize.width, minimumSize.width), maximumSize.width),
            height: min(max(rawSize.height, minimumSize.height), maximumSize.height)
        )
        let iconSize = min(
            max(document.iconSize ?? defaultIconSize, minimumIconSize),
            maximumIconSize
        )

        return DMGWindowLayout(
            contentSize: contentSize,
            backgroundImageURL: background,
            backgroundColor: document.backgroundColor,
            iconPositions: document.iconPositions,
            iconSize: iconSize
        )
    }

    // MARK: - Background

    public static func resolveBackgroundImage(
        mountPoint: URL,
        document: DSStoreDocument
    ) -> URL? {
        if let alias = document.backgroundAlias,
           let fileName = resolveAliasFileName(alias),
           let url = backgroundImage(mountPoint: mountPoint, fileName: fileName) {
            return url
        }

        let backgroundDirectory = mountPoint.appendingPathComponent(".background")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: backgroundDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "gif"]
        return entries
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    /// 只接受纯文件名，拒绝任何路径分隔或上跳片段。
    public static func backgroundImage(mountPoint: URL, fileName: String) -> URL? {
        guard !fileName.isEmpty,
              !fileName.contains("/"),
              !fileName.contains("\\"),
              fileName != ".",
              fileName != "..",
              !fileName.hasPrefix("..") else {
            return nil
        }

        let candidates = [
            mountPoint.appendingPathComponent(".background").appendingPathComponent(fileName),
            mountPoint.appendingPathComponent(fileName)
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 把 `.DS_Store` 里的 alias 数据解析成文件名（仅取 `lastPathComponent`）。
    public static func resolveAliasFileName(_ alias: Data) -> String? {
        guard let bookmark = CFURLCreateBookmarkDataFromAliasRecord(
            nil, alias as CFData
        )?.takeRetainedValue() else {
            return nil
        }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark as Data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }
        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            return nil
        }
        return name
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run:
```bash
cd <repo-root> && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -30
```
Expected: `DMGWindowLayoutTests` 8 个用例通过。

- [ ] **Step 5: Commit**

```bash
git add Sources/AZipCore/DMGWindowLayout.swift Tests/AZipCoreTests/DMGWindowLayoutTests.swift
git commit -m "feat(core): 根据 .DS_Store 计算 DMG 窗口布局"
```

---

## Task 6: VolumeEntry 与目录扫描

**Files:**
- Create: `Sources/AZipCore/VolumeEntry.swift`
- Test: `Tests/AZipCoreTests/VolumeScannerTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `VolumeEntry { id: URL, url: URL, name: String, kind: Kind, byteSize: Int64?, isHidden: Bool }`
  - `VolumeEntry.Kind { folder, application, symbolicLink, file }`
  - `VolumeScanner.ignoredNames: Set<String>`
  - `VolumeScanner.scan(directory: URL) throws -> [VolumeEntry]`
  - `VolumeScanner.applications(in entries: [VolumeEntry]) -> [VolumeEntry]`

- [ ] **Step 1: 写失败测试**

`Tests/AZipCoreTests/VolumeScannerTests.swift`:

```swift
import XCTest
@testable import AZipCore

final class VolumeScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AZipScanTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try makeApp(named: "MultiChat.app")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Docs"), withIntermediateDirectories: true
        )
        try Data("hello".utf8).write(to: root.appendingPathComponent("readme.txt"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".background"), withIntermediateDirectories: true
        )
        try Data([]).write(to: root.appendingPathComponent(".DS_Store"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Applications"),
            withDestinationURL: URL(fileURLWithPath: "/Applications")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFiltersHiddenAndSystemEntries() throws {
        let entries = try VolumeScanner.scan(directory: root)
        let names = entries.map(\.name)

        XCTAssertFalse(names.contains(".DS_Store"))
        XCTAssertFalse(names.contains(".background"))
        XCTAssertFalse(names.contains("Applications"), "指向 /Applications 的符号链接不应出现")
        XCTAssertTrue(names.contains("MultiChat.app"))
        XCTAssertTrue(names.contains("Docs"))
        XCTAssertTrue(names.contains("readme.txt"))
    }

    func testClassifiesKinds() throws {
        let entries = try VolumeScanner.scan(directory: root)
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.kind) })

        XCTAssertEqual(byName["MultiChat.app"], .application)
        XCTAssertEqual(byName["Docs"], .folder)
        XCTAssertEqual(byName["readme.txt"], .file)
    }

    func testSortsFoldersAndAppsBeforeFiles() throws {
        let entries = try VolumeScanner.scan(directory: root)
        let firstThree = Set(entries.prefix(3).map(\.name))
        XCTAssertTrue(firstThree.contains("MultiChat.app"))
        XCTAssertTrue(firstThree.contains("Docs"))
    }

    func testApplicationsHelper() throws {
        let entries = try VolumeScanner.scan(directory: root)
        XCTAssertEqual(VolumeScanner.applications(in: entries).map(\.name), ["MultiChat.app"])
    }

    func testReportsFileSize() throws {
        let entries = try VolumeScanner.scan(directory: root)
        let readme = try XCTUnwrap(entries.first { $0.name == "readme.txt" })
        XCTAssertEqual(readme.byteSize, 5)
        XCTAssertNil(entries.first { $0.name == "Docs" }?.byteSize)
    }

    private func makeApp(named name: String) throws {
        let bundle = root.appendingPathComponent(name)
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data().write(to: macOS.appendingPathComponent("Binary"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:
```bash
cd <repo-root> && xcodegen generate >/dev/null && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -20
```
Expected: 编译失败，提示 `cannot find 'VolumeScanner' in scope`。

- [ ] **Step 3: 实现 VolumeEntry 与 VolumeScanner**

`Sources/AZipCore/VolumeEntry.swift`:

```swift
import Foundation

public struct VolumeEntry: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable {
        case folder
        case application
        case symbolicLink
        case file
    }

    public let id: URL
    public let url: URL
    public let name: String
    public let kind: Kind
    public let byteSize: Int64?
    public let isHidden: Bool

    public init(
        url: URL,
        kind: Kind,
        byteSize: Int64?,
        isHidden: Bool
    ) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        self.kind = kind
        self.byteSize = byteSize
        self.isHidden = isHidden
    }
}

public enum VolumeScanner {
    public static let ignoredNames: Set<String> = [
        ".DS_Store",
        ".background",
        ".VolumeIcon.icns",
        ".fseventsd",
        ".Trashes",
        ".Spotlight-V100",
        ".TemporaryItems",
        ".com.apple.timemachine.donotpresent"
    ]

    public static func scan(directory: URL) throws -> [VolumeEntry] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
            .nameKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        )

        var entries: [VolumeEntry] = []
        for url in urls {
            let name = url.lastPathComponent
            if ignoredNames.contains(name) { continue }

            let values = try? url.resourceValues(forKeys: Set(keys))
            let isSymbolicLink = values?.isSymbolicLink ?? false

            if isSymbolicLink {
                if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path),
                   destination == "/Applications" {
                    continue
                }
                entries.append(
                    VolumeEntry(url: url, kind: .symbolicLink, byteSize: nil, isHidden: values?.isHidden ?? false)
                )
                continue
            }

            let isDirectory = values?.isDirectory ?? false
            let kind: VolumeEntry.Kind
            if isDirectory {
                kind = url.pathExtension.lowercased() == "app" ? .application : .folder
            } else {
                kind = .file
            }

            let size: Int64? = isDirectory
                ? nil
                : Int64(values?.fileAllocatedSize ?? values?.fileSize ?? 0)

            entries.append(
                VolumeEntry(url: url, kind: kind, byteSize: size, isHidden: values?.isHidden ?? false)
            )
        }

        return entries.sorted { lhs, rhs in
            let lhsRank = rank(lhs.kind)
            let rhsRank = rank(rhs.kind)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    public static func applications(in entries: [VolumeEntry]) -> [VolumeEntry] {
        entries.filter { $0.kind == .application }
    }

    private static func rank(_ kind: VolumeEntry.Kind) -> Int {
        switch kind {
        case .application: return 0
        case .folder: return 1
        case .file: return 2
        case .symbolicLink: return 3
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run:
```bash
cd <repo-root> && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -30
```
Expected: `VolumeScannerTests` 5 个用例通过。

- [ ] **Step 5: Commit**

```bash
git add Sources/AZipCore/VolumeEntry.swift Tests/AZipCoreTests/VolumeScannerTests.swift
git commit -m "feat(core): 扫描挂载卷内容并过滤系统条目"
```

---

## Task 7: QuarantineCleaner

**Files:**
- Create: `Sources/AZipCore/QuarantineCleaner.swift`
- Test: `Tests/AZipCoreTests/QuarantineCleanerTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `QuarantineResult { removed: Int, failed: [URL] }`（`Sendable`）
  - `QuarantineCleaner.remove(at url: URL) -> QuarantineResult`
  - `QuarantineCleaner.hasQuarantine(at url: URL) -> Bool`

- [ ] **Step 1: 写失败测试**

`Tests/AZipCoreTests/QuarantineCleanerTests.swift`:

```swift
import XCTest
@testable import AZipCore

final class QuarantineCleanerTests: XCTestCase {
    private var app: URL!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AZipQuarantineTest-\(UUID().uuidString)")
        app = root.appendingPathComponent("Fake.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: macOS.appendingPathComponent("Fake"))
        try Data("plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))

        for target in allPaths() {
            setQuarantine(target)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: app.deletingLastPathComponent())
    }

    func testDetectsQuarantine() {
        XCTAssertTrue(QuarantineCleaner.hasQuarantine(at: app))
    }

    func testRemovesQuarantineRecursively() {
        let result = QuarantineCleaner.remove(at: app)

        XCTAssertEqual(result.failed.count, 0)
        XCTAssertGreaterThanOrEqual(result.removed, 2)
        for path in allPaths() {
            XCTAssertFalse(QuarantineCleaner.hasQuarantine(at: path), "残留隔离属性：\(path.path)")
        }
    }

    func testIsIdempotent() {
        _ = QuarantineCleaner.remove(at: app)
        let second = QuarantineCleaner.remove(at: app)
        XCTAssertEqual(second.removed, 0)
        XCTAssertEqual(second.failed.count, 0)
    }

    private func allPaths() -> [URL] {
        [
            app,
            app.appendingPathComponent("Contents"),
            app.appendingPathComponent("Contents/Info.plist"),
            app.appendingPathComponent("Contents/MacOS"),
            app.appendingPathComponent("Contents/MacOS/Fake")
        ]
    }

    private func setQuarantine(_ url: URL) {
        let value = "0081;00000000;Safari;"
        value.withCString { pointer in
            url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return }
                _ = setxattr(path, "com.apple.quarantine", pointer, strlen(pointer), 0, 0)
            }
        }
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:
```bash
cd <repo-root> && xcodegen generate >/dev/null && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -20
```
Expected: 编译失败，提示 `cannot find 'QuarantineCleaner' in scope`。

- [ ] **Step 3: 实现 QuarantineCleaner**

`Sources/AZipCore/QuarantineCleaner.swift`:

```swift
import Darwin
import Foundation

public struct QuarantineResult: Sendable, Equatable {
    public let removed: Int
    public let failed: [URL]

    public init(removed: Int, failed: [URL]) {
        self.removed = removed
        self.failed = failed
    }
}

public enum QuarantineCleaner {
    public static let attributeName = "com.apple.quarantine"

    /// 递归移除隔离属性。
    ///
    /// 必须进入 `.app` 包内部，因此枚举时同时关闭隐藏文件跳过与包跳过。
    public static func remove(at url: URL) -> QuarantineResult {
        var removed = 0
        var failed: [URL] = []

        for target in allURLs(in: url) {
            let outcome = removeAttribute(at: target)
            switch outcome {
            case .removed:
                removed += 1
            case .absent:
                break
            case .failed:
                failed.append(target)
            }
        }
        return QuarantineResult(removed: removed, failed: failed)
    }

    public static func hasQuarantine(at url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, attributeName, nil, 0, 0, 0) > 0
        }
    }

    // MARK: - Private

    private enum Outcome {
        case removed
        case absent
        case failed
    }

    private static func allURLs(in root: URL) -> [URL] {
        var urls = [root]
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return urls
        }
        for case let url as URL in enumerator {
            urls.append(url)
        }
        return urls
    }

    private static func removeAttribute(at url: URL) -> Outcome {
        url.withUnsafeFileSystemRepresentation { path -> Outcome in
            guard let path else { return .failed }
            if removexattr(path, attributeName, 0) == 0 {
                return .removed
            }
            return errno == ENOATTR ? .absent : .failed
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run:
```bash
cd <repo-root> && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -30
```
Expected: `QuarantineCleanerTests` 3 个用例通过。

- [ ] **Step 5: Commit**

```bash
git add Sources/AZipCore/QuarantineCleaner.swift Tests/AZipCoreTests/QuarantineCleanerTests.swift
git commit -m "feat(core): 递归移除 com.apple.quarantine"
```

---

## Task 8: AppInstaller

**Files:**
- Create: `Sources/AZipCore/LaunchServicesRegistrar.swift`
- Create: `Sources/AZipCore/AppInstaller.swift`
- Test: `Tests/AZipCoreTests/AppInstallerTests.swift`

**Interfaces:**
- Consumes: `ProcessRunner.run`、`QuarantineCleaner.remove`、`LaunchServicesRegistrar.register`
- Produces:
  - `InstallRequest { sourceApp: URL, targetDirectory: URL, overwrite: Bool, trashHandler: @Sendable (URL) -> Bool }`
  - `InstallError { invalidSource(URL), targetNotWritable(URL), conflict(URL), copyFailed(String), moveFailed(String) }`
  - `AppInstaller.install(_:progress:) async throws -> URL`
  - `AppInstaller.pendingBackups(in:) -> [URL]`
  - `AppInstaller.moveToTrash(_:) -> Bool`
  - `AppInstaller.stagingPrefix` / `AppInstaller.backupPrefix`

- [ ] **Step 1: 写失败测试**

`Tests/AZipCoreTests/AppInstallerTests.swift`:

```swift
import XCTest
@testable import AZipCore

final class AppInstallerTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var targetDirectory: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AZipInstallerTest-\(UUID().uuidString)")
        source = root.appendingPathComponent("Source/Fake.app")
        targetDirectory = root.appendingPathComponent("Applications")
        try makeFakeApp(at: source, marker: "v1")
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testInstallsApp() async throws {
        let installed = try await AppInstaller.install(
            InstallRequest(sourceApp: source, targetDirectory: targetDirectory, overwrite: false)
        )

        XCTAssertEqual(installed.lastPathComponent, "Fake.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
        let marker = try String(contentsOf: installed.appendingPathComponent("Contents/MacOS/marker"), encoding: .utf8)
        XCTAssertEqual(marker, "v1")
    }

    func testThrowsConflictWhenTargetExistsWithoutOverwrite() async throws {
        _ = try await AppInstaller.install(
            InstallRequest(sourceApp: source, targetDirectory: targetDirectory, overwrite: false)
        )

        do {
            _ = try await AppInstaller.install(
                InstallRequest(sourceApp: source, targetDirectory: targetDirectory, overwrite: false)
            )
            XCTFail("应当抛出冲突")
        } catch let error as InstallError {
            guard case .conflict = error else {
                return XCTFail("错误类型不符：\(error)")
            }
        }
    }

    func testOverwriteReplacesAppAndTrashesOldVersion() async throws {
        _ = try await AppInstaller.install(
            InstallRequest(sourceApp: source, targetDirectory: targetDirectory, overwrite: false)
        )

        try makeFakeApp(at: source, marker: "v2")

        let trashed = TrashSpy()
        let installed = try await AppInstaller.install(
            InstallRequest(
                sourceApp: source,
                targetDirectory: targetDirectory,
                overwrite: true,
                trashHandler: { url in trashed.record(url) }
            )
        )

        let marker = try String(contentsOf: installed.appendingPathComponent("Contents/MacOS/marker"), encoding: .utf8)
        XCTAssertEqual(marker, "v2")
        XCTAssertEqual(trashed.urls.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashed.urls[0].path))
    }

    func testRejectsNonWritableTarget() async throws {
        let readOnly = root.appendingPathComponent("ReadOnly")
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path)
        }

        do {
            _ = try await AppInstaller.install(
                InstallRequest(sourceApp: source, targetDirectory: readOnly, overwrite: false)
            )
            XCTFail("应当抛出权限错误")
        } catch let error as InstallError {
            guard case .targetNotWritable = error else {
                return XCTFail("错误类型不符：\(error)")
            }
        }
    }

    func testRejectsNonApplicationSource() async throws {
        let folder = root.appendingPathComponent("NotAnApp")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        do {
            _ = try await AppInstaller.install(
                InstallRequest(sourceApp: folder, targetDirectory: targetDirectory, overwrite: false)
            )
            XCTFail("应当抛出无效源错误")
        } catch let error as InstallError {
            guard case .invalidSource = error else {
                return XCTFail("错误类型不符：\(error)")
            }
        }
    }

    func testLeavesNoStagingResidue() async throws {
        _ = try await AppInstaller.install(
            InstallRequest(sourceApp: source, targetDirectory: targetDirectory, overwrite: false)
        )

        let leftovers = try FileManager.default
            .contentsOfDirectory(atPath: targetDirectory.path)
            .filter { $0.hasPrefix(AppInstaller.stagingPrefix) }
        XCTAssertTrue(leftovers.isEmpty, "残留 staging：\(leftovers)")
    }

    func testFindsPendingBackups() async throws {
        let backup = targetDirectory.appendingPathComponent("\(AppInstaller.backupPrefix)abc.app")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)

        XCTAssertEqual(AppInstaller.pendingBackups(in: targetDirectory), [backup])
    }

    // MARK: - Helpers

    private func makeFakeApp(at url: URL, marker: String) throws {
        try? FileManager.default.removeItem(at: url)
        let macOS = url.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: macOS.appendingPathComponent("marker"))
        try Data("<plist/>".utf8).write(to: url.appendingPathComponent("Contents/Info.plist"))
    }
}

private final class TrashSpy: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var urls: [URL] = []

    @discardableResult
    func record(_ url: URL) -> Bool {
        lock.lock()
        urls.append(url)
        lock.unlock()
        try? FileManager.default.removeItem(at: url)
        return true
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:
```bash
cd <repo-root> && xcodegen generate >/dev/null && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -20
```
Expected: 编译失败，提示 `cannot find 'AppInstaller' in scope`。

- [ ] **Step 3: 实现 LaunchServicesRegistrar**

`Sources/AZipCore/LaunchServicesRegistrar.swift`:

```swift
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
```

- [ ] **Step 4: 实现 AppInstaller**

`Sources/AZipCore/AppInstaller.swift`:

```swift
import Foundation

public struct InstallRequest: Sendable {
    public let sourceApp: URL
    public let targetDirectory: URL
    public let overwrite: Bool
    public let trashHandler: @Sendable (URL) -> Bool

    public init(
        sourceApp: URL,
        targetDirectory: URL,
        overwrite: Bool,
        trashHandler: @escaping @Sendable (URL) -> Bool = AppInstaller.moveToTrash
    ) {
        self.sourceApp = sourceApp
        self.targetDirectory = targetDirectory
        self.overwrite = overwrite
        self.trashHandler = trashHandler
    }
}

public enum InstallError: Error, Sendable {
    case invalidSource(URL)
    case targetNotWritable(URL)
    case conflict(URL)
    case copyFailed(String)
    case moveFailed(String)
}

public enum AppInstaller {
    public static let stagingPrefix = ".azip-staging-"
    public static let backupPrefix = ".azip-backup-"

    public static func install(
        _ request: InstallRequest,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        let fileManager = FileManager.default
        let source = request.sourceApp

        let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        guard source.pathExtension.lowercased() == "app", isDirectory else {
            throw InstallError.invalidSource(source)
        }

        let targetDirectory = request.targetDirectory
        guard fileManager.isWritableFile(atPath: targetDirectory.path) else {
            throw InstallError.targetNotWritable(targetDirectory)
        }

        let finalURL = targetDirectory.appendingPathComponent(source.lastPathComponent)
        if fileManager.fileExists(atPath: finalURL.path), !request.overwrite {
            throw InstallError.conflict(finalURL)
        }

        let stagingRoot = targetDirectory
            .appendingPathComponent("\(stagingPrefix)\(UUID().uuidString)")
        let stagingApp = stagingRoot.appendingPathComponent(source.lastPathComponent)

        do {
            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

            let totalBytes = directorySize(source)
            let progressTask = Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    let copied = directorySize(stagingApp)
                    if totalBytes > 0 {
                        progress(min(1.0, Double(copied) / Double(totalBytes)))
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { progressTask.cancel() }

            let copy = try await ProcessRunner.run(
                "/usr/bin/ditto",
                ["--rsrc", "--extattr", "--acl", source.path, stagingApp.path],
                timeoutSeconds: 900
            )
            progressTask.cancel()
            guard copy.status == 0 else {
                throw InstallError.copyFailed(copy.stderr.isEmpty ? "ditto 退出码 \(copy.status)" : copy.stderr)
            }
            progress(1.0)

            var backupURL: URL?
            if fileManager.fileExists(atPath: finalURL.path) {
                let backup = targetDirectory
                    .appendingPathComponent("\(backupPrefix)\(UUID().uuidString).app")
                try fileManager.moveItem(at: finalURL, to: backup)
                backupURL = backup
            }

            do {
                try fileManager.moveItem(at: stagingApp, to: finalURL)
            } catch {
                if let backupURL {
                    try? fileManager.moveItem(at: backupURL, to: finalURL)
                }
                throw InstallError.moveFailed(error.localizedDescription)
            }

            _ = QuarantineCleaner.remove(at: finalURL)
            await LaunchServicesRegistrar.register(finalURL)

            if let backupURL {
                _ = request.trashHandler(backupURL)
            }

            try? fileManager.removeItem(at: stagingRoot)
            return finalURL
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        }
    }

    public static func pendingBackups(in targetDirectory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: targetDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix(backupPrefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 移入废纸篓（可恢复），不使用删除。
    public static func moveToTrash(_ url: URL) -> Bool {
        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private

    private static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

Run:
```bash
cd <repo-root> && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -30
```
Expected: `AppInstallerTests` 7 个用例通过。

- [ ] **Step 6: Commit**

```bash
git add Sources/AZipCore/AppInstaller.swift Sources/AZipCore/LaunchServicesRegistrar.swift Tests/AZipCoreTests/AppInstallerTests.swift
git commit -m "feat(core): 实现带备份与回滚的应用安装器"
```

---

## Task 9: FileAssociation

**Files:**
- Create: `Sources/AZipCore/FileAssociation.swift`
- Test: `Tests/AZipCoreTests/FileAssociationTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `FileAssociationService.diskImageUTIs: [String]`
  - `FileAssociationService.currentHandler(for:) -> String?`
  - `FileAssociationService.isDefault(bundleID:) -> Bool`
  - `FileAssociationService.setDefault(bundleID:) throws`
  - `FileAssociationService.restoreSystemDefault() throws`
  - `FileAssociationError { setFailed(uti: String, status: OSStatus) }`

- [ ] **Step 1: 写失败测试（只读，禁止改变系统状态）**

`Tests/AZipCoreTests/FileAssociationTests.swift`:

```swift
import XCTest
@testable import AZipCore

final class FileAssociationTests: XCTestCase {
    func testDeclaresBothDiskImageUTIs() {
        XCTAssertEqual(
            FileAssociationService.diskImageUTIs,
            ["com.apple.disk-image-udif", "public.disk-image"]
        )
    }

    func testCanQueryCurrentHandlerWithoutMutating() {
        let handler = FileAssociationService.currentHandler(for: "public.disk-image")
        XCTAssertNotNil(handler, "系统应当至少有默认的磁盘映像处理程序")
    }

    func testIsDefaultIsFalseForUnknownBundle() {
        XCTAssertFalse(FileAssociationService.isDefault(bundleID: "com.dengpeng.AZip.not-installed"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:
```bash
cd <repo-root> && xcodegen generate >/dev/null && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -20
```
Expected: 编译失败，提示 `cannot find 'FileAssociationService' in scope`。

- [ ] **Step 3: 实现 FileAssociation**

`Sources/AZipCore/FileAssociation.swift`:

```swift
import CoreServices
import Foundation

public enum FileAssociationError: Error, Sendable {
    case setFailed(uti: String, status: OSStatus)
}

public enum FileAssociationService {
    /// 具体 UTI 优先，父类型兜底。Finder 双击 dmg 时两者都会被查询。
    public static let diskImageUTIs = ["com.apple.disk-image-udif", "public.disk-image"]

    public static let systemDiskImageHandler = "com.apple.DiskImageMounter"

    public static func currentHandler(for uti: String) -> String? {
        guard let unmanaged = LSCopyDefaultRoleHandlerForContentType(
            uti as CFString, .all
        ) else {
            return nil
        }
        return unmanaged.takeRetainedValue() as String
    }

    public static func isDefault(bundleID: String) -> Bool {
        diskImageUTIs.contains { currentHandler(for: $0) == bundleID }
    }

    public static func setDefault(bundleID: String) throws {
        for uti in diskImageUTIs {
            let status = LSSetDefaultRoleHandlerForContentType(
                uti as CFString, .all, bundleID as CFString
            )
            if status != noErr {
                throw FileAssociationError.setFailed(uti: uti, status: status)
            }
        }
    }

    public static func restoreSystemDefault() throws {
        try setDefault(bundleID: systemDiskImageHandler)
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run:
```bash
cd <repo-root> && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -30
```
Expected: `FileAssociationTests` 3 个用例通过。

- [ ] **Step 5: Commit**

```bash
git add Sources/AZipCore/FileAssociation.swift Tests/AZipCoreTests/FileAssociationTests.swift
git commit -m "feat(core): 支持设置 .dmg 默认打开程序"
```

---

## Task 10: 毛玻璃窗口与状态机

**Files:**
- Create: `Sources/AZipApp/Views/VisualEffectBackground.swift`
- Create: `Sources/AZipApp/Views/WindowConfigurator.swift`
- Create: `Sources/AZipApp/DMGSessionModel.swift`

> `RootWindow` 与 `AZipApp` 的接线放在 Task 11，因为 `RootWindow` 依赖 Task 11 创建的 `NavigationBar` / `GridContentView` / `LayoutContentView`。

**Interfaces:**
- Consumes: `DiskImageMounter`、`DSStoreReader`、`DMGWindowLayout`、`VolumeScanner`、`AppInstaller`、`FileAssociationService`
- Produces:
  - `SessionState { idle, mounting, browsing([VolumeEntry], DMGWindowLayout?), installing(URL, Double), failed(String) }`
  - `DMGSessionModel`（`@MainActor`、`ObservableObject`）：`open(dmgURL:)`、`enter(_:)`、`goUp()`、`closeSession()`、`state`、`currentDirectoryName`
  - `BannerMessage { text: String, isError: Bool }`

- [ ] **Step 1: 写 VisualEffectBackground**

`Sources/AZipApp/Views/VisualEffectBackground.swift`:

```swift
import AppKit
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
```

- [ ] **Step 2: 写 WindowConfigurator**

`Sources/AZipApp/Views/WindowConfigurator.swift`:

```swift
import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.minSize = NSSize(width: 480, height: 320)
    }
}
```

- [ ] **Step 3: 写 DMGSessionModel**

`Sources/AZipApp/DMGSessionModel.swift`:

```swift
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
```

- [ ] **Step 4: 构建验证**

Run:
```bash
cd <repo-root> && ./Scripts/build.sh
```
Expected: `BUILD SUCCEEDED`（`DMGSessionModel` 只依赖 Core，可独立编译）。

- [ ] **Step 5: Commit**

```bash
git add Sources/AZipApp/DMGSessionModel.swift Sources/AZipApp/Views/VisualEffectBackground.swift Sources/AZipApp/Views/WindowConfigurator.swift
git commit -m "feat(app): 毛玻璃窗口元件与会话状态机"
```

---

## Task 11: 内容区视图

**Files:**
- Create: `Sources/AZipApp/Views/FileTile.swift`
- Create: `Sources/AZipApp/Views/GridContentView.swift`
- Create: `Sources/AZipApp/Views/LayoutContentView.swift`
- Create: `Sources/AZipApp/Views/NavigationBar.swift`
- Create: `Sources/AZipApp/Views/RootWindow.swift`
- Create: `Sources/AZipApp/OpenPanel.swift`
- Modify: `Sources/AZipApp/AZipApp.swift`
- Modify: `Sources/AZipApp/AppDelegate.swift`
- Test: 无（视图层由 Task 14 的手动验收覆盖）

**Interfaces:**
- Consumes: `VolumeEntry`、`DMGWindowLayout`
- Produces:
  - `FileTile(entry:iconSize:onOpen:)`
  - `GridContentView(entries:onOpen:)`
  - `LayoutContentView(layout:entries:onOpen:)`
  - `NavigationBar(title:canGoUp:onBackToRoot:onUp:)`

- [ ] **Step 1: 写 FileTile**

`Sources/AZipApp/Views/FileTile.swift`:

```swift
import AppKit
import AZipCore
import SwiftUI

struct FileTile: View {
    let entry: VolumeEntry
    var iconSize: CGFloat = 64
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)

            Text(entry.name)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal, 2)
                .frame(maxWidth: iconSize + 28)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(isHovering ? 0.18 : 0))
        )
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: onOpen)
        .onDrag {
            NSItemProvider(contentsOf: entry.url) ?? NSItemProvider()
        }
        .help(entry.name)
    }
}
```

- [ ] **Step 2: 写 GridContentView**

`Sources/AZipApp/Views/GridContentView.swift`:

```swift
import AZipCore
import SwiftUI

struct GridContentView: View {
    let entries: [VolumeEntry]
    let onOpen: (VolumeEntry) -> Void

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(entries) { entry in
                    FileTile(entry: entry) {
                        onOpen(entry)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 3: 写 LayoutContentView**

`Sources/AZipApp/Views/LayoutContentView.swift`:

```swift
import AppKit
import AZipCore
import SwiftUI

struct LayoutContentView: View {
    let layout: DMGWindowLayout
    let entries: [VolumeEntry]
    let onOpen: (VolumeEntry) -> Void

    private var positionedEntries: [VolumeEntry] {
        entries.filter { layout.iconPositions[$0.name] != nil }
    }

    private var unpositionedEntries: [VolumeEntry] {
        entries.filter { layout.iconPositions[$0.name] == nil }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundColor

            if let url = layout.backgroundImageURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .frame(width: image.size.width, height: image.size.height, alignment: .topLeading)
            }

            ForEach(positionedEntries) { entry in
                let point = layout.iconPositions[entry.name] ?? .zero
                FileTile(entry: entry, iconSize: layout.iconSize) {
                    onOpen(entry)
                }
                .position(x: point.x, y: point.y)
            }

            if !unpositionedEntries.isEmpty {
                VStack {
                    Spacer()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(unpositionedEntries) { entry in
                                FileTile(entry: entry, iconSize: layout.iconSize) {
                                    onOpen(entry)
                                }
                            }
                        }
                        .padding(12)
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private var backgroundColor: some View {
        if let components = layout.backgroundColor, components.count >= 4 {
            Color(
                .sRGB,
                red: components[0],
                green: components[1],
                blue: components[2],
                opacity: components[3]
            )
        } else {
            Color.clear
        }
    }
}
```

- [ ] **Step 4: 写 NavigationBar**

`Sources/AZipApp/Views/NavigationBar.swift`:

```swift
import SwiftUI

struct NavigationBar: View {
    let title: String
    let canGoUp: Bool
    let onBackToRoot: () -> Void
    let onUp: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBackToRoot) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(!canGoUp)
            .keyboardShortcut("[", modifiers: .command)
            .help("返回根目录 ⌘[")

            Button(action: onUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(!canGoUp)
            .keyboardShortcut(.upArrow, modifiers: .command)
            .help("上一级 ⌘↑")

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}
```

- [ ] **Step 5: 写 RootWindow**

`Sources/AZipApp/Views/RootWindow.swift`:

```swift
import AZipCore
import SwiftUI

struct RootWindow: View {
    @ObservedObject var model: DMGSessionModel

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow)

            VStack(spacing: 0) {
                NavigationBar(
                    title: model.currentDirectoryName,
                    canGoUp: !model.navigationStack.isEmpty,
                    onBackToRoot: model.goBackToRoot,
                    onUp: model.goUp
                )
                Divider().opacity(0.15)
                content
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(WindowConfigurator())
        .frame(minWidth: 480, minHeight: 320)
        .onDisappear {
            model.closeSession()
        }
        .overlay(alignment: .top) {
            if let banner = model.banner {
                Text(banner.text)
                    .font(.system(size: 11))
                    .foregroundStyle(banner.isError ? Color.red : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 52)
                    .onTapGesture { model.banner = nil }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            placeholder("把 .dmg 文件拖到这里，或按 ⌘O 打开")
        case .mounting:
            ProgressView("正在挂载…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .browsing(entries, layout):
            if let layout, model.navigationStack.isEmpty {
                LayoutContentView(layout: layout, entries: entries, onOpen: model.enter)
            } else {
                GridContentView(entries: entries, onOpen: model.enter)
            }
        case .installing(_, let progress):
            ProgressView("正在安装…", value: progress)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            placeholder(message)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

`onDisappear` 负责关窗时卸载卷（对应 spec 7.3）。

- [ ] **Step 6: 写 OpenPanel 并接线 App 入口**

`Sources/AZipApp/OpenPanel.swift`:

```swift
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
```

`Sources/AZipApp/AZipApp.swift`:

```swift
import SwiftUI

@main
struct AZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DMGSessionModel.shared

    var body: some Scene {
        WindowGroup("AZip") {
            RootWindow(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("打开…") {
                    OpenPanel.openDMG { url in
                        model.open(dmgURL: url)
                    }
                }
                .keyboardShortcut("o")
            }
        }
    }
}
```

`Sources/AZipApp/AppDelegate.swift`:

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DMGSessionModel.shared.offerAssociationIfNeeded()
        DMGSessionModel.shared.reportPendingBackups()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "dmg" {
            DMGSessionModel.shared.open(dmgURL: url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
```

- [ ] **Step 7: 在 DMGSessionModel 中补 `reportPendingBackups()`**

在 `DMGSessionModel.swift` 的 `offerAssociationIfNeeded()` 之后追加：

```swift
    func reportPendingBackups() {
        let backups = AppInstaller.pendingBackups(in: URL(fileURLWithPath: "/Applications"))
        guard !backups.isEmpty else { return }
        banner = BannerMessage(
            text: "上次安装未完成，旧版本备份位于：\(backups[0].path)",
            isError: true
        )
    }
```

- [ ] **Step 8: 构建并运行**

Run:
```bash
cd <repo-root> && ./Scripts/build.sh
open build/Build/Products/Debug/AZip.app
```
Expected: 编译通过；窗口为圆角毛玻璃，顶部有导航胶囊，底部暂时没有安装栏（Task 12 添加）。

- [ ] **Step 9: Commit**

```bash
git add Sources/AZipApp
git commit -m "feat(app): 添加导航栏、网格与按 DS_Store 定位的内容视图"
```

---

## Task 12: 安装流程 UI

**Files:**
- Create: `Sources/AZipApp/Views/BottomBar.swift`
- Create: `Sources/AZipApp/Views/InstallTargetSheet.swift`
- Create: `Sources/AZipApp/Views/InstallConflictSheet.swift`
- Modify: `Sources/AZipApp/Views/RootWindow.swift`
- Modify: `Sources/AZipApp/DMGSessionModel.swift`

**Interfaces:**
- Consumes: `DMGSessionModel.rootApplications`、`DMGSessionModel.requestInstall(_:)`、`pendingApps`、`pendingConflict`
- Produces: `BottomBar(model:)`、`InstallTargetSheet(entries:onSelect:)`、`InstallConflictSheet(appName:onConfirm:onCancel:)`

- [ ] **Step 1: 写 BottomBar**

`Sources/AZipApp/Views/BottomBar.swift`:

```swift
import AZipCore
import SwiftUI

struct BottomBar: View {
    @ObservedObject var model: DMGSessionModel

    private var isInstalling: Bool {
        if case .installing = model.state { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 10) {
            if case .browsing = model.state {
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                if let first = model.rootApplications.first {
                    model.requestInstall(first)
                }
            } label: {
                Label("安装应用", systemImage: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.rootApplications.isEmpty || isInstalling)
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var statusText: String {
        let count = model.rootApplications.count
        switch count {
        case 0: return "此磁盘映像没有可安装的应用程序"
        case 1: return "可安装：\(model.rootApplications[0].name)"
        default: return "\(count) 个应用程序可安装"
        }
    }
}
```

- [ ] **Step 2: 写 InstallTargetSheet**

`Sources/AZipApp/Views/InstallTargetSheet.swift`:

```swift
import AppKit
import AZipCore
import SwiftUI

struct InstallTargetSheet: View {
    let entries: [VolumeEntry]
    let onSelect: (VolumeEntry) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择要安装的应用程序")
                .font(.headline)

            List(entries) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                            .resizable()
                            .frame(width: 32, height: 32)
                        Text(entry.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 240)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
```

- [ ] **Step 3: 写 InstallConflictSheet**

`Sources/AZipApp/Views/InstallConflictSheet.swift`:

```swift
import SwiftUI

struct InstallConflictSheet: View {
    let appName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("应用程序已存在")
                .font(.headline)
            Text("「\(appName)」已在「应用程序」文件夹中。覆盖安装会把旧版本移到废纸篓。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("覆盖安装", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
```

- [ ] **Step 4: 把 BottomBar 与两个 sheet 接进 RootWindow**

把 `RootWindow` 的 `body` 改成（在原实现基础上只加三处标记了 `// 新增` 的行）：

```swift
    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow)

            VStack(spacing: 0) {
                NavigationBar(
                    title: model.currentDirectoryName,
                    canGoUp: !model.navigationStack.isEmpty,
                    onBackToRoot: model.goBackToRoot,
                    onUp: model.goUp
                )
                Divider().opacity(0.15)
                content
                BottomBar(model: model)          // 新增
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(WindowConfigurator())
        .frame(minWidth: 480, minHeight: 320)
        .onDisappear {
            model.closeSession()
        }
        .sheet(item: $model.pendingApps) { selection in          // 新增
            InstallTargetSheet(
                entries: selection.entries,
                onSelect: { entry in
                    model.installDirectly(entry)
                },
                onCancel: { model.pendingApps = nil }
            )
        }
        .sheet(item: $model.pendingConflict) { request in        // 新增
            InstallConflictSheet(
                appName: request.appURL.lastPathComponent,
                onConfirm: {
                    model.confirmConflict()
                },
                onCancel: { model.pendingConflict = nil }
            )
        }
    }
```

- [ ] **Step 5: 修正 BottomBar 的安装入口**

`BottomBar` 中点击按钮时调用 `model.requestInstall`，当存在多个 app 时 `requestInstall` 会设置 `pendingApps` 弹出选择面板；选择面板里的 `installDirectly` 直接开始安装，不会重复弹面板。

- [ ] **Step 6: 构建验证**

Run:
```bash
cd <repo-root> && ./Scripts/build.sh
```
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 7: Commit**

```bash
git add Sources/AZipApp
git commit -m "feat(app): 添加安装按钮、应用选择与覆盖确认界面"
```

---

## Task 13: 文件关联弹窗与设置

**Files:**
- Create: `Sources/AZipApp/Views/AssociationSheet.swift`
- Create: `Sources/AZipApp/Views/SettingsView.swift`
- Modify: `Sources/AZipApp/Views/RootWindow.swift`
- Modify: `Sources/AZipApp/AZipApp.swift`

**Interfaces:**
- Consumes: `FileAssociationService`
- Produces: `AssociationSheet`、`SettingsView`

- [ ] **Step 1: 写 AssociationSheet**

`Sources/AZipApp/Views/AssociationSheet.swift`:

```swift
import AppKit
import AZipCore
import SwiftUI
import UniformTypeIdentifiers

struct AssociationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("didOfferFileAssociation") private var didOffer = false

    @State private var isChecked = true
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("关联文件格式")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(for: .diskImage))
                    .resizable()
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DMG 磁盘映像")
                        .font(.system(size: 13))
                    Text(".dmg")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $isChecked)
                    .labelsHidden()
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

            Text("勾选后，双击 .dmg 文件将由 AZip 打开。之后可在设置中修改。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("以后再说") {
                    didOffer = true
                    dismiss()
                }
                Button("确认关联") {
                    apply()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func apply() {
        didOffer = true
        guard isChecked else {
            dismiss()
            return
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.dengpeng.AZip"
        do {
            try FileAssociationService.setDefault(bundleID: bundleID)
            dismiss()
        } catch {
            errorText = "设置失败：\(error)"
        }
    }
}
```

- [ ] **Step 2: 写 SettingsView**

`Sources/AZipApp/Views/SettingsView.swift`:

```swift
import AZipCore
import SwiftUI

struct SettingsView: View {
    @AppStorage("didOfferFileAssociation") private var didOffer = false

    @State private var isDefault = false
    @State private var message: String?

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.dengpeng.AZip"
    }

    var body: some View {
        Form {
            Section("文件关联") {
                HStack {
                    Text("DMG 磁盘映像")
                    Spacer()
                    Text(isDefault ? "已关联" : "未关联")
                        .foregroundStyle(isDefault ? .green : .secondary)
                }

                HStack {
                    Button("设为默认打开方式") {
                        setDefault()
                    }
                    Button("恢复系统默认") {
                        restore()
                    }
                    Button("重新显示关联提示") {
                        didOffer = false
                        message = "下次启动时会再次提示"
                    }
                }

                if let message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 200)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        isDefault = FileAssociationService.isDefault(bundleID: bundleID)
    }

    private func setDefault() {
        do {
            try FileAssociationService.setDefault(bundleID: bundleID)
            message = "已设为默认打开方式"
        } catch {
            message = "设置失败：\(error)"
        }
        refresh()
    }

    private func restore() {
        do {
            try FileAssociationService.restoreSystemDefault()
            message = "已恢复系统默认"
        } catch {
            message = "恢复失败：\(error)"
        }
        refresh()
    }
}
```

- [ ] **Step 3: 把关联弹窗接进 RootWindow**

在 `RootWindow` 的 `.sheet(item: $model.pendingConflict) { ... }` 之后追加：

```swift
        .sheet(isPresented: $model.showAssociationSheet) {
            AssociationSheet()
        }
```

- [ ] **Step 4: 在 App 中注册设置窗口**

在 `AZipApp.swift` 的 `WindowGroup` 之后追加：

```swift
        Settings {
            SettingsView()
        }
```

- [ ] **Step 5: 构建验证**

Run:
```bash
cd <repo-root> && ./Scripts/build.sh
```
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6: 手动验证关联弹窗**

Run（只重置本应用自己的提示标记，不触碰任何用户文件）：
```bash
defaults delete com.dengpeng.AZip didOfferFileAssociation 2>/dev/null || true
open build/Build/Products/Debug/AZip.app
```
Expected: 首次启动弹出「关联文件格式」毛玻璃 sheet；点「确认关联」后，在 Finder 中右键任一 dmg →「显示简介」→「打开方式」应显示 AZip。

- [ ] **Step 7: Commit**

```bash
git add Sources/AZipApp
git commit -m "feat(app): 添加文件关联弹窗与设置页"
```

---

## Task 14: 集成测试与验收

**Files:**
- Create: `Scripts/make_test_dmg.sh`
- Create: `Tests/AZipCoreTests/IntegrationTests.swift`
- Create: `docs/superpowers/specs/2026-10-23-azip-manual-acceptance.md`

**Interfaces:**
- Consumes: 全部 Core 模块
- Produces: 可重复执行的集成测试入口

- [ ] **Step 1: 写测试 dmg 生成脚本**

`Scripts/make_test_dmg.sh`:

```bash
#!/bin/bash
set -euo pipefail

OUT="${1:-/tmp/AZipTest.dmg}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/TestApp.app/Contents/MacOS"
cat > "$STAGE/TestApp.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>TestApp</string>
	<key>CFBundleIdentifier</key>
	<string>com.dengpeng.AZip.TestApp</string>
	<key>CFBundleName</key>
	<string>TestApp</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
</dict>
</plist>
PLIST

printf '#!/bin/sh\necho AZip test app\n' > "$STAGE/TestApp.app/Contents/MacOS/TestApp"
chmod +x "$STAGE/TestApp.app/Contents/MacOS/TestApp"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$STAGE/.background"
printf '\x89PNG\r\n\x1a\n' > "$STAGE/.background/background.png"

rm -f "$OUT"
hdiutil create -volname "AZipTest" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
echo "created: $OUT"
```

```bash
chmod +x Scripts/make_test_dmg.sh
```

- [ ] **Step 2: 写集成测试**

`Tests/AZipCoreTests/IntegrationTests.swift`:

```swift
import XCTest
@testable import AZipCore

final class IntegrationTests: XCTestCase {
    private var workDirectory: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["AZIP_INTEGRATION"] == "1",
            "设置 AZIP_INTEGRATION=1 才运行集成测试"
        )
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AZipIntegration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
    }

    func testMountScanInstallDetach() async throws {
        let dmg = workDirectory.appendingPathComponent("TestApp.dmg")
        try await makeDMG(at: dmg)

        let mount = try await DiskImageMounter.attach(dmg)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mount.mountPoint.path))

        addTeardownBlock {
            try? await DiskImageMounter.detach(mount)
        }

        let entries = try VolumeScanner.scan(directory: mount.mountPoint)
        let apps = VolumeScanner.applications(in: entries)
        XCTAssertEqual(apps.map(\.name), ["TestApp.app"])

        let targetDirectory = workDirectory.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let installed = try await AppInstaller.install(
            InstallRequest(sourceApp: apps[0].url, targetDirectory: targetDirectory, overwrite: false)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertFalse(QuarantineCleaner.hasQuarantine(at: installed))

        try await DiskImageMounter.detach(mount)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mount.mountPoint.path))
    }

    func testDetachFailsForMissingVolume() async throws {
        let result = MountResult(
            mountPoint: URL(fileURLWithPath: "/Volumes/AZipDoesNotExist-\(UUID().uuidString)"),
            deviceEntry: "/dev/disk999",
            volumeName: "DoesNotExist"
        )
        do {
            try await DiskImageMounter.detach(result)
            XCTFail("对一个不存在的设备卸载应当失败")
        } catch {
            // 预期：hdiutil 返回非 0 并抛出 toolFailed
        }
    }

    private func makeDMG(at url: URL) async throws {
        let stage = workDirectory.appendingPathComponent("stage")
        let macOS = stage.appendingPathComponent("TestApp.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data("hi".utf8).write(to: macOS.appendingPathComponent("TestApp"))
        try Data("<plist/>".utf8).write(to: stage.appendingPathComponent("TestApp.app/Contents/Info.plist"))
        try FileManager.default.createSymbolicLink(
            at: stage.appendingPathComponent("Applications"),
            withDestinationURL: URL(fileURLWithPath: "/Applications")
        )

        let result = try await ProcessRunner.run(
            "/usr/bin/hdiutil",
            ["create", "-volname", "AZipTest", "-srcfolder", stage.path, "-ov", "-format", "UDZO", url.path],
            timeoutSeconds: 120
        )
        XCTAssertEqual(result.status, 0, result.stderr)
    }
}
```

- [ ] **Step 3: 运行集成测试**

Run:
```bash
cd <repo-root> && xcodegen generate >/dev/null && AZIP_INTEGRATION=1 xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -30
```
Expected: `IntegrationTests` 2 个用例通过（若系统拒绝挂载，检查 `/Volumes` 权限与是否有残留挂载）。

- [ ] **Step 4: 写手动验收清单**

`docs/superpowers/specs/2026-10-23-azip-manual-acceptance.md`:

```markdown
# AZip 首期手动验收清单

| 编号 | 步骤 | 预期 |
|---|---|---|
| A1 | 运行 `scripts/make_test_dmg.sh /tmp/AZipTest.dmg` 后双击该文件 | AZip 打开并显示 TestApp.app |
| A2 | 打开一个带自定义背景的真实 dmg（如微信安装包） | 背景图原尺寸显示在左上角，图标落在背景箭头指向的位置 |
| A3 | 把窗口拉大 | 背景图不拉伸，右侧/底部露出背景色或透明 |
| A4 | 双击 `Applications` 符号链接 | 无反应或提示，不崩溃（该链接已被过滤） |
| A5 | 点「安装应用」，选择 TestApp | 进度条走完后提示成功 |
| A6 | `xattr -p com.apple.quarantine /Applications/TestApp.app` | 输出 `No such xattr` |
| A7 | 再次运行同一 dmg 并安装 | 弹出「应用程序已存在」，取消后 /Applications 无变化 |
| A8 | 确认覆盖安装 | 旧版本出现在废纸篓，新版本就位 |
| A9 | 安装完成后检查 `ls /Volumes` | 挂载卷已消失 |
| A10 | 关闭窗口后检查 `ls /Volumes` | 无残留挂载 |
| A11 | 设置 → 恢复系统默认 → 双击任一 dmg | 由系统磁盘映像工具打开 |
| A12 | 把 dmg 内文件拖到 Finder 桌面 | 文件被复制出来（拖拽导出可用） |
```

- [ ] **Step 5: 全量测试**

Run:
```bash
cd <repo-root> && xcodegen generate >/dev/null && xcodebuild test -project AZip.xcodeproj -scheme AZip -destination 'platform=macOS' -quiet 2>&1 | tail -30
```
Expected: 所有单元测试通过，2 个集成测试跳过（`XCTSkip`）。

- [ ] **Step 6: Commit**

```bash
git add Scripts Tests docs/superpowers/specs/2026-10-23-azip-manual-acceptance.md
git commit -m "test: 添加集成测试与手动验收清单"
```

---

## 完成标准

| 条件 | 验证 |
|---|---|
| 全部单元测试通过 | `xcodebuild test ... -quiet` 无失败 |
| 集成测试在 `AZIP_INTEGRATION=1` 下通过 | 同上，带环境变量 |
| 手动验收 A1–A12 全部通过 | 按清单逐项勾选 |
| 真实 dmg 安装后首启无「移到废纸篓」弹窗 | 实际双击启动已安装的 app |
