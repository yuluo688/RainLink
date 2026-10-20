# Linux 退出生命周期与 Flutter SDK 升级

日期：2026-10-20。基于 `0f80987cac940518e77f23816c5490223debff76` 及未提交修改，延续[通用系统功能验收](linux-desktop-system-services.md)。用户已授权直接操作桌面；本轮仍使用独立 QA 用户、数据库和网络命名空间，没有使用真实订阅或用户凭据。

## 修改与原因

旧 Flutter 3.27.4 的实际退出堆栈包含视图释放后的光标回调、滚动管理器弱引用清理和文件选择插件在引擎销毁时重新创建通道。见[旧版堆栈](linux-flutter-lifecycle/baseline-backtrace.log)。

项目基线升至 **Flutter 3.29.3 / Dart 3.7.2**。框架提交为 `ea121f8859e4b13e47a8f845e4586164519588bc`，引擎为 `cf56914b326edb0ccb123ffdc60f00060bd513fa`；Windows/Linux 使用独立 SDK，其他项目的 SDK 没有修改。`.fvmrc`、最低 Flutter 版本和依赖锁文件同步更新；Dart 语言版本保留 3.6，避免无关格式改动。两项直接依赖 `path`、`stack_trace` 随 SDK 升级，间接依赖由实际 pub 解算生成。

新版引擎解决前两类对象问题；`file_selector_linux 0.9.3+2` 的通道问题仍可复现，见[升级后、runner 修复前](linux-flutter-lifecycle/sdk-329-before-runner-fix-backtrace.log)。现在在 GTK 窗口销毁子视图之前，用公开 messenger API 释放该插件的 Pigeon handler，并将回调生命周期绑定到 messenger。没有修改生成的插件、Flutter 源码、引擎私有结构或日志输出；后续升级文件选择插件时须复核通道名称。

另外修复直接运行 Android Gradle 构建时沿用旧版号的问题：构建脚本从 pubspec 同步版本，本轮 APK 实际为 **0.1.0+4**。Android 和 Windows 启动器验证器增加报告输出参数，日常 Windows 构建将证据写到 build；此前被构建刷新过的历史启动器报告恢复到原验收内容，最新摘要另存[本轮报告](linux-flutter-lifecycle/windows-launcher.json)。

## 实际验收

Linux 为隔离 Debian 13 chroot、普通 UID 1000、Xvfb/Openbox、真实 Xfce panel 与 Dunst；GTK 辅助功能总线实际运行。测试依赖的 SQLite 开发库和中文字体只装入 QA 环境。

| 检查 | 结果与证据 |
| --- | --- |
| Flutter 单元/组件 | Linux **473 项通过**；[日志](linux-flutter-lifecycle/flutter-unit-tests.log) |
| 格式与分析 | **284 个 Dart 文件无改动、分析无问题**；[格式](linux-flutter-lifecycle/flutter-format-final.log)、[分析](linux-flutter-lifecycle/flutter-analyze-final.log) |
| GTK 保存弹窗 | **1 项完整流程通过**：实际取消后无文件/无成功提示，重试保存到含空格路径，CSV 写入并回读；启用 `G_DEBUG=fatal-warnings`；[日志](linux-flutter-lifecycle/file-export.log)、[结果](linux-flutter-lifecycle/file-export-result.json)、[实际弹窗](linux-flutter-lifecycle/picker-save.png) |
| 原生系统功能回归 | **1 项完整流程通过**：自动启动回读、托盘恢复、面板消失恢复窗口/重启注册、真实通知与分组跳转、关闭托盘后继续通知；[日志](linux-flutter-lifecycle/desktop-integration.log)、[结果](linux-flutter-lifecycle/native-integration.json) |
| Linux 成品包 | 含空格路径解压；**3 次退出码均为 0、4 次关闭到托盘/恢复**，最后两次从真实托盘菜单协议退出；仅应用开启致命 GTK 警告；[运行结果](linux-flutter-lifecycle/release-result.json)、[实际脚本](linux-flutter-lifecycle/verify_lifecycle_release.py) |
| Windows Release | 完整 Flutter、Go 宿主、启动器与资源检查通过，Release 引擎摘要匹配；[构建](linux-flutter-lifecycle/windows-build.log)、[启动器](linux-flutter-lifecycle/windows-launcher.json) |
| 布局 | Windows/Linux 各 **3 项通过、54 张截图**；包括桌面两尺寸、移动两尺寸、深浅主题和大字号 IPv6；[Windows](linux-flutter-lifecycle/windows-layout.log)、[Linux](linux-flutter-lifecycle/linux-layout.log)、[108 张摘要](linux-flutter-lifecycle/layout-captures.json) |
| Android 构建 | 普通应用及测试 APK 构建、**5 项 Kotlin 单元通过**；Lint **0 错误、4 警告**；[构建](linux-flutter-lifecycle/android-build.log)、[单元/Lint 摘要](linux-flutter-lifecycle/build-checks.json) |
| Android 产物 | CRC、Debug 签名、实际版号、全部原生库 16 KB 对齐及嵌入核心摘要通过；[报告](linux-flutter-lifecycle/android-package.json) |
| 源码一致性 | Windows 工作区与 Linux QA 的 **746 项输入一致**；[输入](linux-flutter-lifecycle/source-inputs.json)、[结果](linux-flutter-lifecycle/source-verification.json) |

新增[Linux 文件导出回归](../../app/integration_test/linux_file_export_test.dart)仅允许 Linux 隔离测试标识与指定的独立 XDG 配置目录。它调用真实导出服务，以测试进程 PID 限定 GTK 弹窗，驱动子进程有超时和终止清理。复现需要 `xdotool`、`xprop`、ImageMagick、Python，以及 `RAINLINK_TEST_DESKTOP=isolated`；不打开用户数据库。[桌面系统集成](../../app/integration_test/linux_desktop_integration_test.dart)仍使用真实服务；本轮将已显示窗口的位置设为固定坐标，避免扩大后截图被屏幕裁切。

本轮两次环境问题保留原记录：第一次单元测试因缺少 `libsqlite3.so` 入口失败，安装真正的 SQLite 开发包后 473 项通过；[失败日志](linux-flutter-lifecycle/flutter-unit-tests-missing-sqlite.log)和[安装输入](linux-flutter-lifecycle/sqlite-test-package-inputs.json)保留。首次托盘重启测试把 `G_DEBUG=fatal-warnings` 传给了外部 Xfce 面板，面板因隔离会话没有 session manager 的警告退出；[面板独立复现](linux-flutter-lifecycle/strict-panel-probe.log)确认原因。恢复面板正常环境后原断言全部通过；RainLink 自身的严格退出与保存弹窗测试继续开启致命 GTK 警告。

## 画面与 Figma

Bridge 当前连接 `unsaved-mvfj9942-5y6aivnm` / RainLink。重新原生导出设置节点 `2:19743`，见[当前设计稿](linux-flutter-lifecycle/figma-settings-current.png)，与[Linux 深色设置](linux-flutter-lifecycle/general-dark-panel.png)、[浅色设置](linux-flutter-lifecycle/general-light-panel.png)对照。前阶段实时导出的 44 个 SVG 本轮逐项摘要复核仍一致，见[资产记录](linux-flutter-lifecycle/figma-assets-unchanged.json)，没有重复生成图标。

108 张布局已按页复查，未发现 SDK 升级引入新的溢出或图标缺失。保留[Linux 紧凑概览](linux-flutter-lifecycle/overview-960-dark-fixture.png)、[移动概览](linux-flutter-lifecycle/overview-mobile-393-dark-fixture.png)及各平台接触表。移动截图来自桌面渲染器的隔离 fixture，不代表本轮 Android/iOS 原生运行。图表数据和时钟不同，Figma 的示例版本、网络分数、通知默认值也与真实能力不同，因此不声称全页面逐像素一致。

## 产物与剩余边界

- Linux：`build/RainLink-linux-x64-preview.tar.xz`，同内容副本 `build/RainLink-linux-x64-lifecycle.tar.xz`；**32,469,740 bytes**，SHA-256 `3247fba4b7abde640cbea2bb07d5b6398598011196541ac0f8da4b0079c279d1`。79 个归档项、55 个运行资产、权限与逐文件摘要通过，见[打包结果](linux-flutter-lifecycle/linux-package.json)与[包清单](linux-flutter-lifecycle/linux-bundle.json)。旧的 desktop-services 包及报告保留。Go 宿主沿用前阶段 `3c94988871e41f58fcfa486b7c58ce749b1b2cac6a217ffa9c1cf586f46394e4`，没有宣称本轮重跑全部 Go 网络场景。
- Android：`build/RainLink-0.1.0+4-android-debug-preview.apk`；**213,510,959 bytes**，SHA-256 `9be22c402dc7930a519c8e7e93a93920c50df4e5b501bef273637d31815438db`。这是本地 Debug 签名包；本轮没有安装手机或重跑设备端授权、切网、传输。原生库与签名以本轮产物报告为准。
- Windows：完整 Release 在 `app/build/windows/x64/runner/Release`，本轮没有替换历史 ZIP，也没有重跑在线更新事务。

最终三次 Release 日志均仍包含 Flutter 的 `The implicit view cannot be removed`，见[首次退出](linux-flutter-lifecycle/launch-1.log)、[托盘退出](linux-flutter-lifecycle/launch-2.log)、[重开再退出](linux-flutter-lifecycle/launch-3.log)。它来自引擎无条件移除隐式视图的上游路径，不是 GLib warning；本轮严格退出没有出现此前的 GTK critical、弱引用或无引擎通道警告，但日志没有被屏蔽或宣称完全为空。

Windows 原版 tag 的 `shared.bat` 在本机生成的工具 stamp 仅为 `":"`；SDK 源码未修改，版本由 Git 提交、引擎摘要和实际构建共同核实，不能仅用此 stamp 判断版本。SDK 元数据分别保存为 [Windows](linux-flutter-lifecycle/windows-sdk-version.json) 与 [Linux](linux-flutter-lifecycle/sdk-329-version.json)。

完整 GNOME/Plasma/Wayland、多发行版、真实注销自动启动、休眠/切网、正式分发、macOS/iOS 及其余产品能力仍继续开发。公开 Linux `capabilities.tun` 保持 **false**。代码未自动提交、推送或发布；完整五平台目标尚未完成。

本轮证据文件摘要见[索引](linux-flutter-lifecycle/evidence.json)。
