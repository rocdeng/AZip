# AZip 首期手动验收清单

| 编号 | 步骤 | 预期 |
|---|---|---|
| A1 | 运行 `Scripts/make_test_dmg.sh /tmp/AZipTest.dmg` 后双击该文件 | AZip 打开并显示 TestApp.app |
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
