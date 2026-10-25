# 压缩包浏览：实现说明

记录「用 AZip 浏览压缩包」这条链路的架构、关键参数，以及踩过的坑。

## 一、入口

| 入口 | 触发方式 | 代码位置 |
|---|---|---|
| Finder 服务 | 右键 zip → 服务 → 用 AZip 浏览压缩包 | `AppDelegate.browseArchive(_:userData:error:)` |
| 调试 | `AZIP_BROWSE=/path/to.zip open -a AZip` | `applicationDidFinishLaunching` |

服务声明在 `project.yml` 的 `Info.plist`：

```yaml
NSServices:
  - NSMessage: browseArchive
    NSPortName: AZip
    NSMenuItem:
      default: 用 AZip 浏览压缩包
    NSSendFileTypes:
      - public.item
    NSRequiredContext:
      NSApplicationIdentifier: com.apple.finder
```

启动时注册：

```swift
NSApp.servicesProvider = self
NSUpdateDynamicServices()
```

## 二、分层

| 层 | 文件 | 职责 |
|---|---|---|
| 读取 | `AZipCore/ArchiveReader.swift` | `bsdtar -tvf` 列出条目、按需解压单个条目 |
| 状态 | `AZipApp/ArchiveBrowseSession.swift` | 当前包/当前目录/预提取/解压到目录 |
| 窗口 | `AZipApp/BrowseWindowController.swift` | 浏览模式专用 `NSWindow` |
| 视图 | `AZipApp/Views/BrowseView.swift` | 列表、导航、拖拽、底部按钮 |

浏览窗口的内容是 `RootWindow`（与主窗口共用毛玻璃和标题配置），由
`browse.isActive` 决定渲染浏览界面。

## 三、条目解析

`bsdtar -tvf` 在 `LC_ALL=C` 下输出稳定格式：

```
-rw-rw-r--  0 0 0 14612 Apr  7  2026 Keys-22.1.0/prod.keys
```

解析要点：

| 项 | 做法 |
|---|---|
| 环境 | 子进程注入 `LC_ALL=C` / `LANG=C` |
| 分段 | `split(separator: " ", maxSplits: 8)`，前 8 段元数据，第 9 段起是路径（可含空格） |
| 类型 | 权限首字符为 `d` 即目录 |
| 日期 | 依次尝试 `MMM d HH:mm` 与 `MMM d yyyy`（`en_US_POSIX`） |

### 缺失目录的补全

部分工具打包时不写目录条目（实测 `Keys-22.1.0.zip` 只有一行
`Keys-22.1.0/prod.keys`），根目录会显示为空。

`ArchiveReader.synthesizeMissingDirectories` 会按路径反推补出所有缺失的父目录，
目录路径统一以 `/` 结尾。视图按 `entry.parentPath` 过滤直接子项，因此补全后
根目录能正常显示 `Keys-22.1.0` 文件夹。

## 四、交互

| 操作 | 行为 |
|---|---|
| 双击文件夹 | 只改变 `currentPath`，不重新解压 |
| 双击文件 | `bsdtar -xf <archive> -C <tmp> <path>` 解出单个文件，再交给系统打开 |
| 拖拽 | 进入目录时**后台预提取**该层全部内容，拖拽直接给真实文件 URL |
| 右键 | 「打开」/「导出到…」 |
| 底部「解压缩到…」 | 选父目录 → 解压到 `<父目录>/<包名>/` |
| 关闭 | 退出 app |

### 预提取与拖拽

SwiftUI 的 `.onDrag` 是同步的，必须立刻给出真实存在的文件 URL，因此：

- 进入目录（含首次加载、返回上级）时触发 `prefetchCurrentDirectory()`
- 目录条目会**递归展开**为全部子项一起提取，保证空目录也能拖出
- 预提取未完成时 `dragURL(for:)` 返回 nil，该行拖拽暂时无效（可重试或用右键导出）

## 五、解压到指定目录

复用 `ArchiveExtractor.extract`，只是目标目录由用户选择：

```
destination = <选中的父目录>/<压缩包文件名去掉扩展名>
```

进度复用通用任务浮窗（`TaskPanelModel` + `ExtractionWindowController`），
完成后播放提示音并在 Finder 中定位结果。**不会**退出 app——浏览会话继续。

## 六、踩过的坑

| 现象 | 根因 | 解法 |
|---|---|---|
| 服务启动后只有 Dock 图标跳动，窗口不出现 | SwiftUI `WindowGroup` 在服务启动时根本不创建窗口（日志实测 `windows=0`），任何激活重试都无效 | 浏览模式改用自建的 `NSWindow`（`BrowseWindowController`） |
| 把窗口拖到屏幕右边，双击目录后跳回中间 | 状态变化触发窗口配置，配置里调用了 `window.center()` | 只改尺寸并保留 origin，仅在首次出现时居中 |
| 关闭浏览窗口时设置界面一闪而过 | `browse.close()` 后 `isActive=false`，主窗口先渲染了一帧 idle 分支 | 关闭时直接 `exit(0)`，不给 idle 分支渲染机会 |
| `Keys-22.1.0.zip` 显示为空 | 归档内没有目录条目，根目录无直接子项 | 按路径反推补全目录条目 |
| 空目录拖不出来 | 预提取只处理文件 | 目录条目连同其全部子项一起提取 |
| 关闭窗口后进程残留 | `NSApp.terminate` 停在系统终止协商，run loop 不再调度主队列 | 清理完成后 `exit(0)` |

## 七、与双击行为的边界

| 操作 | 走哪条链路 |
|---|---|
| Finder 双击 `.dmg` | 主窗口：挂载 + 安装（`DMGSessionModel`） |
| Finder 双击压缩包 | 独立解压浮窗，完成后退出（`ArchiveSession`） |
| Finder 右键 → 服务 | 浏览窗口（`ArchiveBrowseSession` + `BrowseWindowController`） |
| 直接运行 AZip | 设置窗口 |
