<div align="center">

<img src="Onecook/Resources/GhostCook.icon/Assets/%E9%9C%93%E8%99%B9%E5%BD%A9%E8%99%B9%E5%B9%BD%E7%81%B5%E5%9B%BE%E6%A0%87.png" width="144" height="144" alt="GhostCook Logo" />

<h1>GhostCook</h1>

<p>常用控制，一触即达。<br />Your everyday Mac controls, one click away.</p>

<p>
  <img src="https://img.shields.io/badge/macOS-13%2B-111827?style=flat-square&amp;logo=apple&amp;logoColor=white" alt="macOS 13+" />
  <img src="https://img.shields.io/badge/Swift-5-F05138?style=flat-square&amp;logo=swift&amp;logoColor=white" alt="Swift 5" />
  <img src="https://img.shields.io/badge/UI-AppKit%20%2B%20SwiftUI-6366F1?style=flat-square" alt="AppKit + SwiftUI" />
  <img src="https://img.shields.io/badge/Liquid%20Glass-macOS%2026%2B-A855F7?style=flat-square" alt="Liquid Glass on macOS 26+" />
</p>

<p>
  <a href="#中文">中文</a> · <a href="#english">English</a>
</p>

<p>
  <a href="#快速开始">快速开始</a> · <a href="#核心能力">核心能力</a> · <a href="#开发与验证">开发与验证</a><br />
  <a href="#quick-start">Quick Start</a> · <a href="#features">Features</a> · <a href="#development-and-verification">Development</a>
</p>

</div>

---

<a id="中文"></a>
## 中文

### 项目简介

独立的原生实现，主面板使用 AppKit，设置使用 SwiftUI，不依赖 React、Tauri、Rust 或 WebView。主面板使用系统菜单栏状态项与无箭头 `NSPanel`，正常启动不弹出控制窗口，不显示 Dock 图标。

参考版本：OneTouch `ba2c9d7eb9502ae2964408457a0c480903694421`。本项目使用独立标识 `dev.nialyoung.onecook` 和独立偏好数据，不修改 OneTouch 的配置。应用图标使用提供的 Icon Composer 原文件 `Onecook/Resources/GhostCook.icon`，构建时生成系统图标与旧版 macOS 所需资源。参考仓库未附许可证，公开分发前需确认参考内容的使用授权。

### 核心能力

- 31 个控制项：桌面图标、深色模式、保持唤醒、蓝牙耳机与可读取的电量、专注模式、夜览、屏幕保护、原彩显示、前台应用、麦克风、Xcode 缓存、废纸篓、下载目录、磁盘、剪贴板、隐藏窗口、Dock、电源模式、Music、Spotify、隐藏文件、显示休眠、分辨率、小组件、台前调度、屏幕与键盘清洁、锁屏、退出其他应用、飞书 aily。
- macOS 26 及以上使用 `NSGlassEffectView` 原生液态玻璃；macOS 13–25 使用 `NSVisualEffectView` 背景模糊。
- 设置窗口使用系统 SwiftUI 侧栏与分组表单：基础设置整合语言、主题色（跟随系统 / 亮色 / 暗色）、登录启动、权限与关于；控制项支持搜索、勾选与拖动排序。侧边栏底部直接展示作者邮箱、GitHub 和 X 联系入口；界面文字不小于 14pt。
- 唤醒、深色与专注模式支持定时；偏好、定时截止时间与磁盘保护在本机保存。
- 清理下载和 Xcode 派生数据移入废纸篓；清空废纸篓会永久删除其中内容。下载与废纸篓点击后直接执行；Xcode 缓存清理、推出磁盘与退出其他应用先确认。废纸篓清空在独立后台队列运行，最长等待一小时，期间显示进度并禁止重复执行，不阻塞其他系统控制。

联系入口的 SVG 图标来自 [Simple Icons](https://github.com/simple-icons/simple-icons)（GitHub、X，CC0）与 [Lucide](https://lucide.dev/icons/mail)（邮箱，ISC）；许可随应用资源保留。

### 快速开始

需要 macOS 13+，以及包含 macOS 26+ SDK 的 Xcode 和 XcodeGen；当前默认开发工具路径为 `/Applications/Xcode.app/Contents/Developer`，可通过 `DEVELOPER_DIR` 覆盖。测试工具链需要 macOS 14+。

```sh
./scripts/build.sh
open build/DerivedData/Build/Products/Debug/GhostCook.app
```

也可打开 `Onecook.xcodeproj`，选择 Onecook scheme 运行。工程源配置为 `project.yml`。构建使用 `Developer ID Application: Niall Young (V8GVW783CK)` 签名，需要钥匙串中存在对应证书及私钥。

### 使用方法

点击菜单栏幽灵图标打开控制面板。底栏可打开设置或退出。超过 8 项时列表保持固定高度并滚动。辅助功能仅在引导或对应控制操作时申请；自动化、蓝牙与专注状态权限按系统要求处理。

主面板控制项显示图标、名称与开关，不显示辅助文本或错误弹窗；操作错误记录到系统日志。动作完成后图标短暂显示对勾，剪贴板清空后名称显示“剪贴板已清空”两秒。清空只针对系统当前剪贴板，不删除其他应用保存的剪贴板历史。

在设置的“基础设置 → 关于”点击“检查更新”。更新检查读取 GitHub 公开的最新 Release 页面，不使用 GitHub API，也不需要账号、订阅或 Token。发现较新正式版本后，可通过默认浏览器下载匹配 Mac 架构的 DMG、ZIP 或 PKG；没有合适安装包时打开该版本的发布页面。下载后手动安装，应用不会自动替换自身。版本标签使用 `v0.1.0` 或 `0.1.0` 等数字版本；草稿与预发布不参与检查。

在设置的“控制项”页面勾选并拖动调整控制项；推出磁盘开关支持长按或右键打开保护名单。

### 开发与验证

```sh
./scripts/test.sh
```

自动测试覆盖配置恢复、空选择、排序、定时持久化、31 个符号、真实唤醒断言、材质和滚动布局、命令参数、输出与超时，以及 aily 状态解析；更新测试覆盖版本比较、安装包架构筛选、无发布版本与 HTTP 错误。实际运行界面检查不等于所有系统操作已完成实机验收。

Debug 包可通过明确的诊断参数打开菜单栏面板或设置窗口；此入口不会进入 Release 包：

```sh
open build/DerivedData/Build/Products/Debug/GhostCook.app --args --show-controls
open build/DerivedData/Build/Products/Debug/GhostCook.app --args --show-settings
```

### 常见问题

- 夜览和原彩显示使用经过运行时检查的可选 CoreBrightness 客户端；它们属于非公开系统接口，可能因系统或硬件变化不可用。专注与电源模式通过辅助功能操作系统控制中心，对应控制项需要显示在菜单栏，其标识可能随系统版本改变。
- 无耳机、未安装 Spotify/aily 或不支持的硬件不伪造可用状态。蓝牙连接、电源模式、磁盘推出、键盘拦截与授权流程仍需要对应硬件及系统权限验收。尚未在旧版 macOS 上实机验证模糊回退。
- 飞书 aily 需要 `~/.aily-cli/bin/aily-cli`；启动通过临时 launchd 任务运行，不安装登录任务，退出 GhostCook 不会停止服务。
- 当前构建使用 Developer ID 签名，尚未进行 Apple 公证；从原有 ad-hoc 签名切换后可能需要重新授权辅助功能。独立版本不复用上游的 Tauri 自动更新安装链。
- 正常退出会释放唤醒断言、屏幕清洁和键盘拦截，并尝试关闭定时控制；关闭失败的截止时间保留，下次启动重试。

<a id="english"></a>
## English

### Overview

An independent native implementation with an AppKit menu panel and SwiftUI settings, inspired by [OneTouch](https://github.com/Cherry-Yiran/OneTouch), without React, Tauri, Rust or WebView. A system status item opens an arrowless `NSPanel`; normal launch does not show the panel or a Dock icon.

Reference revision: `ba2c9d7eb9502ae2964408457a0c480903694421`. The separate identifier `dev.nialyoung.onecook` and preference domain leave OneTouch settings untouched. The app icon uses the supplied Icon Composer source `Onecook/Resources/GhostCook.icon`; the build generates the system icon and resources for older macOS versions. No upstream license was included; confirm rights to reference content before public distribution.

### Features

- 31 controls: desktop icons, Dark Mode, Keep Awake, Bluetooth headphones with available battery readings, Focus, Night Shift, screen saver, True Tone, front app, microphone, Xcode cache, Trash, Downloads, disks, clipboard, hide window, Dock, power modes, Music, Spotify, hidden files, display sleep, resolution, widgets, Stage Manager, screen and keyboard cleaning, lock screen, quit other apps, and Feishu aily.
- Native `NSGlassEffectView` Liquid Glass on macOS 26+; `NSVisualEffectView` background blur on macOS 13–25.
- Settings use the system SwiftUI sidebar and grouped form: General combines language, appearance (System / Light / Dark), launch at login, permissions and About; Controls supports search, selection and drag ordering. Author email, GitHub and X links sit directly at the bottom of the sidebar; interface text is at least 14 pt.
- Timers for Keep Awake, Dark Mode and Focus; preferences, deadlines and disk protection persist locally.
- Downloads and Xcode derived data are moved to Trash; emptying Trash permanently deletes its contents. Downloads and Trash execute immediately; Xcode cache cleanup, eject and quit-other-apps actions require confirmation. Emptying Trash runs on a separate background queue with a one-hour timeout, showing progress and preventing duplicate execution while keeping other system controls responsive.

Contact SVG icons come from [Simple Icons](https://github.com/simple-icons/simple-icons) (GitHub and X, CC0) and [Lucide](https://lucide.dev/icons/mail) (email, ISC). Licenses are included in app resources.

### Quick Start

Requires macOS 13+, Xcode with a macOS 26+ SDK, and XcodeGen. Scripts default to `/Applications/Xcode.app/Contents/Developer`; override with `DEVELOPER_DIR`. The test toolchain requires macOS 14+.

```sh
./scripts/build.sh
open build/DerivedData/Build/Products/Debug/GhostCook.app
```

Alternatively, open `Onecook.xcodeproj` and run the Onecook scheme. `project.yml` is the source build configuration. Builds use `Developer ID Application: Niall Young (V8GVW783CK)` and require the matching certificate and private key in Keychain.

### Usage

Click the ghost menu bar icon. The footer opens Settings or Quit. More than eight controls scroll within a fixed-height list. Accessibility is requested through onboarding or related controls; automation, Bluetooth and Focus permissions follow macOS requirements.

The main panel shows each control’s icon, name and switch without secondary text or error alerts. Operation errors are written to the system log. Completed actions briefly show a checkmark; clearing the clipboard displays “Clipboard cleared” for two seconds. Only the current system clipboard is cleared, leaving history stored by other apps untouched.

Click “Check for Updates” in General → About. Checks use the public GitHub latest Release page without the GitHub API, an account, a subscription or a token. When a newer stable release exists, the default browser downloads a DMG, ZIP or PKG matching the Mac architecture; if no suitable installer exists, the release page opens instead. Install the downloaded update manually; the app does not replace itself. Release tags must be numeric versions such as `v0.1.0` or `0.1.0`; drafts and prereleases are excluded.

Select and drag controls in the Controls settings page. Long-press or right-click the eject switch to manage protected disks.

### Development and Verification

```sh
./scripts/test.sh
```

Automated tests cover preference recovery, empty selection, ordering, timer persistence, all 31 symbols, a real wake assertion, material and scrolling layout, command arguments, output and timeout, and aily status parsing; update tests cover version comparison, installer architecture selection, missing releases and HTTP errors. Inspecting the running interface does not establish acceptance of every system operation.

The Debug app supports explicit diagnostic arguments to open the menu panel or settings window; this entry is absent from Release builds:

```sh
open build/DerivedData/Build/Products/Debug/GhostCook.app --args --show-controls
open build/DerivedData/Build/Products/Debug/GhostCook.app --args --show-settings
```

### Troubleshooting

- Night Shift and True Tone use optional runtime-checked CoreBrightness clients. These non-public system interfaces may be unavailable on different hardware or macOS versions. Focus and power modes operate system Control Center through Accessibility; the corresponding items must appear in the menu bar, and their identifiers may change between releases.
- Missing headphones, Spotify/aily installations or unsupported hardware never produce invented availability. Bluetooth connection, power modes, disk eject, keyboard interception and permission flows still require hardware and permission acceptance. The blur fallback has not been tested on an older macOS installation.
- Feishu aily requires `~/.aily-cli/bin/aily-cli`. Startup uses a temporary launchd job without installing a login job. Quitting GhostCook leaves the daemon running.
- Builds use Developer ID signing and have not been notarized by Apple. Switching from the previous ad-hoc signature may require Accessibility authorization again. This independent version does not reuse the upstream Tauri update installer.
- Normal exit releases wake assertions, screen cleaning and keyboard interception, and attempts to turn off timed controls. Failed deadlines remain saved for retry on the next launch.
