# 毛玻璃窗口与解压浮窗：实现说明

本文记录 AZip 两个窗口形态的具体做法、参数取值，以及踩过的坑。目标是让读者（人或模型）不看代码也能复现同样的效果。

## 一、整体结构

| 窗口 | 用途 | 形态 |
|---|---|---|
| 主窗口 | DMG 浏览、安装、设置 | SwiftUI `Window` 场景 + AppKit 注入的毛玻璃底 |
| 解压浮窗 | 解压进度 | 独立 `NSWindow(.borderless)`，纯 AppKit 承载 SwiftUI |

两者共用同一个视觉语言：圆角 14、`.hudWindow` 材质、`.behindWindow` 模糊。

## 二、毛玻璃的通用配方

### 2.1 材质视图参数

```swift
let effect = NSVisualEffectView(frame: container.bounds)
effect.material       = .hudWindow      // 半透明 + 模糊，最接近系统浮窗
effect.blendingMode   = .behindWindow   // 采样窗口背后的内容并实时模糊
effect.state          = .active         // 固定渲染；followsWindowActiveState 在非前台时会退化
effect.alphaValue     = 0.99            // 只调材质层的不透明度，不动 SwiftUI 内容
effect.autoresizingMask = [.width, .height]
```

参数含义（按重要性排序）：

| 参数 | 取值 | 为什么 |
|---|---|---|
| `blendingMode` | `.behindWindow` | 这是「透出背后内容」的开关。`.withinWindow` 只在窗口内部混合，不透背后 |
| `material` | `.hudWindow` | 半透明模糊。`.underWindowBackground` 在 behindWindow 下渲染为**实心**窗口底色，不要用它做透视 |
| `state` | `.active` | `.followsWindowActiveState` 在 app 不在前台时会让材质几乎消失 |
| `alphaValue` | `0.99` | 实测微调值。再低会「太透」，`1.0` 偏实 |

### 2.2 图层顺序（最容易翻车的地方）

```
container (NSView, wantsLayer=true, cornerRadius=14, masksToBounds=true)
├── NSVisualEffectView        ← 必须先加，位于最底层
└── NSHostingView(SwiftUI)    ← 后加，位于材质之上
```

**不能**把 `NSVisualEffectView` 加到 `NSHostingView` 内部：AppKit 的子视图绘制在父视图自身内容之上，材质会整个盖住 SwiftUI 画的所有东西（表现为「窗口里只有模糊背景，文字和按钮全不见了」）。

同理，主窗口里材质视图要加到 `contentView.superview`（`NSThemeFrame`），并 `positioned: .below, relativeTo: contentView`。

### 2.3 布局方式

在 `NSHostingView` 作为容器时，**不要用 Auto Layout 约束**把材质视图钉到四边——宿主视图不参与其子视图的约束布局，材质会停在 0×0，结果是「窗口全透明、没有模糊」。

正确做法：

```swift
let effect = NSVisualEffectView(frame: container.bounds)
effect.autoresizingMask = [.width, .height]
```

## 三、解压浮窗

### 3.1 窗口本身

```swift
let panel = NSWindow(
    contentRect: NSRect(origin: .zero, size: NSSize(width: 380, height: 84)),
    styleMask: [.borderless],     // 无标题栏、无红绿灯
    backing: .buffered,
    defer: false
)
panel.isOpaque            = false
panel.backgroundColor     = .clear
panel.hasShadow           = true
panel.level               = .floating                 // 浮在其他窗口之上
panel.isMovableByWindowBackground = true              // 按住空白处可拖动
panel.collectionBehavior  = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

圆角由容器的 layer 负责，不依赖窗口本身：

```swift
container.wantsLayer = true
container.layer?.cornerRadius = 14
container.layer?.cornerCurve = .continuous
container.layer?.masksToBounds = true
```

### 3.2 内容布局（380×84）

```
┌──────────────────────────────────────────────────────────┐
│ [图标 40]  AZip - 正在解压缩 xxx.zip          (  )  (X)  │
│            ▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░                 │
│            23%  ·  约 4 秒                                │
└──────────────────────────────────────────────────────────┘
```

| 元素 | 规格 |
|---|---|
| 图标 | `NSWorkspace.shared.icon(forFile:)`，40×40 |
| 标题 | 11pt medium，`AZip - 正在解压缩 <文件名>`，单行截断 |
| 进度条 | 自绘：`Capsule` 轨道（前景色 14%）+ `Capsule` 填充（`Color.accentColor`），高 6 |
| 明细 | 10pt secondary，`<百分比>% · 约 N 秒` |
| 关闭 | `xmark.circle.fill` 17pt，运行中=取消，结束后=关闭 |
| 内边距 | 水平 16 / 垂直 12 |

进度条为什么自绘：系统 `ProgressView(.linear)` 在毛玻璃上颜色发灰、几乎看不见填充；自绘胶囊颜色可控，还能加 0.2 秒缓动。

### 3.3 生命周期

```
打开压缩包
  → 主窗口 orderOut（不参与显示）
  → 创建浮窗，level = .floating，居中
  → bsdtar 解压，每 180ms 采样「目标目录条目数 / 归档条目总数」更新进度
  → 成功：停留 1.2 秒 → 关闭浮窗 → NSApp.terminate(nil)
  → 取消：停留 0.6 秒 → 同上
  → 失败：保留浮窗显示原因，用户点 X 后退出
```

进度用「条目数」而不是字节数：对 zip/tar/gz 等所有格式都能统一计算，不需要预读归档元数据。

## 四、主窗口的毛玻璃

| 项 | 参数 |
|---|---|
| 窗口 | `titleVisibility = .visible`、`titlebarAppearsTransparent = true`、`fullSizeContentView`、`isOpaque = false`、`backgroundColor = .clear` |
| 材质 | 同 2.1，`alphaValue = 0.99` |
| 圆角 | SwiftUI `.clipShape(RoundedRectangle(cornerRadius: 14))` |
| 标题 | `AZip` / `AZip - <dmg 文件名>` |
| 内容留白 | 顶部 12pt（标题栏）、底部 78pt（安装栏） |

DMG 内容区额外做了一层「伪毛玻璃」：背景图以 **0.85 不透明度**绘制，底层材质模糊透上来。低于 0.85 会明显发灰，高于 0.92 看不出效果。

## 五、踩过的坑（按代价排序）

| 现象 | 根因 | 解法 |
|---|---|---|
| 窗口里什么都没有，只有模糊底 | 材质视图加在 NSHostingView 内部，盖住了 SwiftUI 内容 | 材质放到宿主视图之下（兄弟视图） |
| 全透明，没有模糊 | 材质视图用 Auto Layout 钉边，停在 0×0 | 用 frame + autoresizingMask |
| 灰板一块，完全不透 | 用了 `.underWindowBackground` 做 behindWindow | 换 `.hudWindow` |
| 进程在跑但没有窗口 | AppKit 窗口状态恢复记住了「无窗口」 | 启动早期注册 `ApplePersistenceIgnoreState = true` |
| 主窗口尺寸/标识互相干扰 | `WindowGroup` 会实例化多个窗口 | 改用单例 `Window` 场景 |
| 解压浮窗被撑到 480×320 | 窗口 `minSize` 与 SwiftUI `.frame(minWidth:)` 限制 | 解压时把 minSize 降到 360×200 |
| 私有 CGS 模糊完全无效 | 纯透明窗口不会触发 backdrop blur | 需要一层半透明底色载体（最终未采用） |

## 六、未采用的方案

| 方案 | 结论 |
|---|---|
| 私有 `CGSSetWindowBackgroundBlurRadius` | 效果接近 Dock，但需要自签受信任证书/私有 API，且纯透明窗口不生效，最终回到 `.hudWindow` |
| `CALayer.backgroundFilters` + `CIGaussianBlur` | 可用，但在 SwiftUI 宿主视图上叠加会与系统材质冲突 |
| 自定义 5 档材质切换 | 仅作调试，已移除 |
