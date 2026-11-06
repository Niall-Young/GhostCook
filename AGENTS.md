# GhostCook

- 本项目是独立的 Swift macOS 菜单栏应用，主面板使用 AppKit，设置使用系统 SwiftUI 侧栏与分组表单；不要引入 WebView、Tauri 或 Web UI。
- 所有界面文字字号不得小于 14pt，包括正文、分组标题、辅助文字、版本信息和联系信息；禁止通过缩放文字规避，空间不足时换行或调整布局。
- 主控制面板保持锚定菜单栏图标的 `NSPanel`；正常启动与再次打开应用时不自动弹出主面板，也不显示 Dock 图标。
- macOS 26 及以上使用原生 `NSGlassEffectView`；macOS 13–25 使用 `NSVisualEffectView` 背景模糊，使用系统语义颜色与控件。
- `project.yml` 是 XcodeGen 工程源配置。修改构建配置后运行 `xcodegen generate`，不要只修改生成的工程。
- 构建使用 `./scripts/build.sh`，测试使用 `./scripts/test.sh`。命令在本项目内运行，构建产物保存在被忽略的 `build/`。
- 系统操作应读取真实状态并报告错误；清理及退出其他应用等操作必须经过确认。测试使用隔离的偏好域，不清空真实废纸篓、下载目录，也不退出用户应用。
