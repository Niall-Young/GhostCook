# Onecook

Swift + AppKit 原生 macOS 菜单栏工具，参考 [OneTouch](https://github.com/Cherry-Yiran/OneTouch) 重写。

[中文](#中文) | [English](#english)

<a id="中文"></a>
## 中文

### 项目简介

独立的原生实现，主面板使用 AppKit，设置使用 SwiftUI，不依赖 React、Tauri、Rust 或 WebView。主面板使用系统菜单栏状态项与无箭头 `NSPanel`，正常启动不弹出控制窗口，不显示 Dock 图标。

参考版本：OneTouch `ba2c9d7eb9502ae2964408457a0c480903694421`。本项目使用独立标识 `dev.nialyoung.onecook` 和独立偏好数据，不修改 OneTouch 的配置。应用图标沿用参考仓库的 `src-tauri/icons/icon.icns`；上游未附许可证，公开分发前需确认图标与参考内容的使用授权。

### 核心能力

- 31 个控制项：桌面图标、深色模式、保持唤醒、蓝牙耳机与可读取的电量、专注模式、夜览、屏幕保护、原彩显示、前台应用、麦克风、Xcode 缓存、废纸篓、下载目录、磁盘、剪贴板、隐藏窗口、Dock、电源模式、Music、Spotify、隐藏文件、显示休眠、分辨率、小组件、台前调度、屏幕与键盘清洁、锁屏、退出其他应用、飞书 aily。
- macOS 26 及以上使用 `NSGlassEffectView` 原生液态玻璃；macOS 13–25 使用 `NSVisualEffectView` 背景模糊。
- 设置窗口使用系统 SwiftUI 侧栏与分组表单：基础设置整合语言、登录启动、权限与关于；控制项支持搜索、勾选与拖动排序。侧边栏底部提供作者邮箱、GitHub 和 X 联系入口。
- 唤醒、深色与专注模式支持定时；偏好、定时截止时间与磁盘保护在本机保存。
- 清理下载和 Xcode 派生数据移入废纸篓；清空废纸篓会永久删除其中内容。清理、推出磁盘与退出其他应用先确认。

### 快速开始

需要 macOS 13+，以及包含 macOS 26+ SDK 的 Xcode 和 XcodeGen；当前默认开发工具路径为 `/Applications/Xcode.app/Contents/Developer`，可通过 `DEVELOPER_DIR` 覆盖。测试工具链需要 macOS 14+。

```sh
./scripts/build.sh
open build/DerivedData/Build/Products/Debug/Onecook.app
```

也可打开 `Onecook.xcodeproj`，选择 Onecook scheme 运行。工程源配置为 `project.yml`。默认使用本机 ad-hoc 签名；可在本地工程配置中选择自己的签名身份。

### 使用方法

点击菜单栏单开关图标打开控制面板。底栏可打开设置或退出。超过 8 项时列表保持固定高度并滚动。辅助功能仅在引导或对应控制操作时申请；自动化、蓝牙与专注状态权限按系统要求处理。

主面板控制项仅显示图标、名称与开关，不显示辅助文本或错误弹窗；操作错误记录到系统日志。

在设置的“控制项”页面勾选并拖动调整控制项；推出磁盘开关支持长按或右键打开保护名单。

### 开发与验证

```sh
./scripts/test.sh
```

自动测试覆盖配置恢复、空选择、排序、定时持久化、31 个符号、真实唤醒断言、材质和滚动布局、命令参数、输出与超时，以及 aily 状态解析。实际运行界面检查不等于所有系统操作已完成实机验收。

Debug 包可通过明确的诊断参数打开菜单栏面板；此入口不会进入 Release 包：

```sh
open build/DerivedData/Build/Products/Debug/Onecook.app --args --show-controls
```

### 常见问题

- 夜览和原彩显示使用经过运行时检查的可选 CoreBrightness 客户端；它们属于非公开系统接口，可能因系统或硬件变化不可用。专注与电源模式通过辅助功能操作系统控制中心，对应控制项需要显示在菜单栏，其标识可能随系统版本改变。
- 无耳机、未安装 Spotify/aily 或不支持的硬件不伪造可用状态。蓝牙连接、电源模式、磁盘推出、键盘拦截与授权流程仍需要对应硬件及系统权限验收。尚未在旧版 macOS 上实机验证模糊回退。
- 飞书 aily 需要 `~/.aily-cli/bin/aily-cli`；启动通过临时 launchd 任务运行，不安装登录任务，退出 Onecook 不会停止服务。
- 当前提供本机 Debug 构建，签名由本地工程配置决定，未做公证；重新签名可能需要重新授权辅助功能。独立版本不复用上游的 Tauri 自动更新安装链。
- 正常退出会释放唤醒断言、屏幕清洁和键盘拦截，并尝试关闭定时控制；关闭失败的截止时间保留，下次启动重试。

<a id="english"></a>
## English

### Overview

An independent native implementation with an AppKit menu panel and SwiftUI settings, inspired by [OneTouch](https://github.com/Cherry-Yiran/OneTouch), without React, Tauri, Rust or WebView. A system status item opens an arrowless `NSPanel`; normal launch does not show the panel or a Dock icon.

Reference revision: `ba2c9d7eb9502ae2964408457a0c480903694421`. The separate identifier `dev.nialyoung.onecook` and preference domain leave OneTouch settings untouched. The app icon comes from the reference repository’s `src-tauri/icons/icon.icns`. No upstream license was included; confirm rights to the icon and reference content before public distribution.

### Features

- 31 controls: desktop icons, Dark Mode, Keep Awake, Bluetooth headphones with available battery readings, Focus, Night Shift, screen saver, True Tone, front app, microphone, Xcode cache, Trash, Downloads, disks, clipboard, hide window, Dock, power modes, Music, Spotify, hidden files, display sleep, resolution, widgets, Stage Manager, screen and keyboard cleaning, lock screen, quit other apps, and Feishu aily.
- Native `NSGlassEffectView` Liquid Glass on macOS 26+; `NSVisualEffectView` background blur on macOS 13–25.
- Settings use the system SwiftUI sidebar and grouped form: General combines language, launch at login, permissions and About; Controls supports search, selection and drag ordering. An author card at the bottom of the sidebar links to email, GitHub and X.
- Timers for Keep Awake, Dark Mode and Focus; preferences, deadlines and disk protection persist locally.
- Downloads and Xcode derived data are moved to Trash; emptying Trash permanently deletes its contents. Cleanup, eject and quit-other-apps actions require confirmation.

### Quick Start

Requires macOS 13+, Xcode with a macOS 26+ SDK, and XcodeGen. Scripts default to `/Applications/Xcode.app/Contents/Developer`; override with `DEVELOPER_DIR`. The test toolchain requires macOS 14+.

```sh
./scripts/build.sh
open build/DerivedData/Build/Products/Debug/Onecook.app
```

Alternatively, open `Onecook.xcodeproj` and run the Onecook scheme. `project.yml` is the source build configuration. The default build uses local ad-hoc signing; select your own signing identity in the local project configuration if needed.

### Usage

Click the single-switch menu bar icon. The footer opens Settings or Quit. More than eight controls scroll within a fixed-height list. Accessibility is requested through onboarding or related controls; automation, Bluetooth and Focus permissions follow macOS requirements.

The main panel shows each control’s icon, name and switch without secondary text or error alerts. Operation errors are written to the system log.

Select and drag controls in the Controls settings page. Long-press or right-click the eject switch to manage protected disks.

### Development and Verification

```sh
./scripts/test.sh
```

Automated tests cover preference recovery, empty selection, ordering, timer persistence, all 31 symbols, a real wake assertion, material and scrolling layout, command arguments, output and timeout, and aily status parsing. Inspecting the running interface does not establish acceptance of every system operation.

The Debug app supports an explicit diagnostic argument to open the menu panel; this entry is absent from Release builds:

```sh
open build/DerivedData/Build/Products/Debug/Onecook.app --args --show-controls
```

### Troubleshooting

- Night Shift and True Tone use optional runtime-checked CoreBrightness clients. These non-public system interfaces may be unavailable on different hardware or macOS versions. Focus and power modes operate system Control Center through Accessibility; the corresponding items must appear in the menu bar, and their identifiers may change between releases.
- Missing headphones, Spotify/aily installations or unsupported hardware never produce invented availability. Bluetooth connection, power modes, disk eject, keyboard interception and permission flows still require hardware and permission acceptance. The blur fallback has not been tested on an older macOS installation.
- Feishu aily requires `~/.aily-cli/bin/aily-cli`. Startup uses a temporary launchd job without installing a login job. Quitting Onecook leaves the daemon running.
- This is a local Debug build whose signing follows the local project configuration, without notarization. Re-signing may require Accessibility authorization again. This independent version does not reuse the upstream Tauri update installer.
- Normal exit releases wake assertions, screen cleaning and keyboard interception, and attempts to turn off timed controls. Failed deadlines remain saved for retry on the next launch.
