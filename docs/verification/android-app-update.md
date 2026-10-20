# Android 应用更新与移动系统栏

日期：2026-10-20。本阶段补齐 Android 直接安装渠道的应用更新，继续复用既有更新页面和组件。macOS/iOS 原生构建仍需 Mac；五平台完整目标尚未完成，Linux 公开 `capabilities.tun` 保持 false。

## 使用行为

- 在“设置 → 更新”检查固定 GitHub 发布源，选择稳定版或包含预览版。启动检查默认关闭，不自动下载或安装。
- Android 选择 `RainLink-<版本名>+<构建号>-android-universal.apk`；Windows 仍选择原有 ZIP，不混用平台资源。缺少摘要、没有对应安装包或版本无效时给出中文状态。
- 下载可取消，完整大小和 SHA-256 校验通过后才显示“安装更新”。点击后先确认，再断开连接、等待网络恢复、暂停后台写入并保存设置，最后交给系统授权和安装确认。
- 授权拒绝或安装取消后保留旧版本和已下载包，恢复页面操作。恢复网络失败时不会打开安装器；安装交接期间阻止重新连接和返回设置列表。
- 打开安装器不计为安装成功。系统必须实际替换包版本；旧进程退出后，通过持久回执在下一次正常启动显示“上次更新已安装”。中断安装显示可重试状态。若旧进程仍返回成功，更新页明确要求重新打开，并停止用旧版本号再次检查更新。
- 移动端自绘页头没有 AppBar，现由应用根节点跟随实际主题设置系统栏对比度：浅色使用深色状态图标和导航指示条，深色反之。主题缓存按应用实例持有，避免同一渲染进程的不同平台布局继承首次平台的 ThemeData。

## 安装边界与生命周期

Flutter 使用薄平台接口；复制、摘要和 PackageManager 检查在原生单线程 worker 执行。来源限应用更新缓存，安装前复制到独占创建的私有 staging 文件，再检查大小、摘要、包名、版本名、递增构建号和当前签名集合。安装交接前重新检查同一份字节，FileProvider 只共享 `cache/updates/install/`，不导出 provider。

准备过程可取消、有超时；取消确认、清理及回执读取有独立的短超时。系统授权和安装确认由用户操作，不用人为短超时中断。原生错误统一映射为安全中文，不回显本机路径或底层异常。Activity 销毁后保留已交给系统读取的那一个包和回执，其余取消/失败路径清理 staging；超过七天的残留在后续准备中回收。

Android 使用系统安装器保障 APK 替换，不复用 Windows 的程序目录/SQLite 回滚机制。正式安装仍要求签名一致。此阶段产物明确为 Debug 预览，未发布正式安装包或创建 GitHub release。

## 实际 Android 验收

唯一设备为本次新建的 `RainLink_Update_QA` API 36 x86_64 AVD，使用独立 ADB server 5047、console 5590 / transport 5591。普通 `main.dart` APK 与原生测试 APK 在隔离应用内运行，没有访问用户数据库、订阅、手机或其他 AVD。

验收后已核对 AVD 身份，通过其本地认证控制端口正常退出，再断开残留测试 transport 并关闭空闲的私有 ADB 5047。测试磁盘与证据保留，默认 ADB 5037、其他设备及 FlClash 未操作，见[清理记录](android-app-update/android/cleanup.json)。

最终原生结果见 [安装证据](android-app-update/android/install-evidence.json) 和 [测试摘要](android-app-update/tests.json)：

1. 三项真实 APK 安全测试通过：私有复制、准备后篡改、摘要/旧版本/错误版本/包名/签名/路径拒绝、浮点构建号拒绝、取消准备和清理。
2. 实际安装来源设置中拒绝授权，JUnit 确认 `permission_denied`，实际安装版本仍为 4。
3. 在系统设置明确授权后，在真实更新确认窗口选择 Cancel，JUnit 确认 `cancelled`，版本仍为 4。
4. 用普通界面保存虚构 HTTP 节点 `QAUpdateNode` 和浅色主题，再在真实系统确认窗口升级到构建 5。PackageManager、正常启动后的 `RainLink 0.1.0+5` 和持久安装回执均核对通过。升级前后受检的节点、分组、本地覆盖、偏好及 schema 8 数据一致，正常重开后节点仍显示。
5. 安装前对浅色主题实际 WindowInsetsController 的状态栏/导航栏标志进行断言；升级后截图复核图标对比度。

成功升级会终止旧的被测进程，`system-install.log` 因此可能记录 `Process crashed`。这一条本身不是通过证据；外部脚本必须同时确认实际构建号、普通新版本启动、回执和受检数据一致才写成功报告。授权和取消各自仍要求明确的 JUnit 通过结果。

验收使用未发布的完整候选副本，仅在副本把构建号 4 改成 5；产品源版本仍为 `0.1.0+4`。最终候选和普通包的输入核对、摘要见 [产物记录](android-app-update/artifacts.json)。图像分别为[系统来源授权](android-app-update/android/install-source-permission.png)、[安装确认](android-app-update/android/installer-install.png)、[升级后版本与回执](android-app-update/android/reopened-updated-app.png)和[保留节点](android-app-update/android/reopened-preserved-node.png)。

初次脚本遇到 UiAutomation 争用、Compose 授权行的子文字不可点击、更新按钮实际名为 Update、继承的 UID AppOp 覆盖应用授权，以及表单标签在 accessibility `hint` 中等问题。已修正脚本并保留失败诊断，最终从新建的受控数据基线完整重跑；没有弱化版本、签名、数据或 JUnit 断言。浅色导航指示条的首次回归也检出 Flutter 预设样式仍用浅色图标，现显式设置并重新验收。

## 自动检查、设计与产物

最终计数、日志路径与摘要以 [tests.json](android-app-update/tests.json) 为准。Flutter 全量包含 Android 安装接口、交接/返回/网络恢复失败、超时、旧进程等待重开、Android/iOS 布局的深浅主题切换，以及既有业务回归。iOS widget 测试只证明 Flutter 行为，不是 Apple 原生验证。

| 检查 | 最终范围 |
| --- | --- |
| Flutter 全量 | 539 项通过，零失败/跳过；静态分析无问题 |
| 格式 | 本阶段 15 个 Dart 文件，最终检查无变化；三个 Python 工具语法检查通过 |
| Android 构建 | 普通 Debug APK、androidTest APK、5 项 Kotlin 单元通过；Lint 0 错误、7 条警告，未屏蔽规则 |
| 原生流程 | 3 项安全测试、拒绝与取消各 1 项 JUnit，另有真实系统升级与受检数据保持；均限独立 AVD |
| 布局与图标 | Windows native runner 44 张深浅主题 fixture；4 个本页使用 SVG 与当前 Figma 导出逐字节一致 |
| 完整包 | Debug 签名、CRC、构建版本、嵌入核心、所有原生库和 ZIP 16 KB 对齐通过 |

更新页的 44 张 fixture 截图覆盖 1440×900、960×640、393×852、320×740@1.3 和深浅主题，包含检查、可用版本、下载、已校验、安装确认及移动等待重开状态；溢出和点击断言通过。[总览](android-app-update/visual-contact-sheet.png)与 [visual](android-app-update/visual/) 保留各画面。移动尺寸由 Windows 原生 runner 渲染，不用于证明系统安装行为。

当前 Figma 文件 `RainLink / unsaved-mvfj9942-5y6aivnm` 的移动更新组件 `59:48458` 和桌面组件 `59:47288` 已读取并保存[参考](android-app-update/reference/)。refresh、download、back、品牌四个原生 SVG 与运行资源逐字节一致，见 [icons.json](android-app-update/reference/icons.json)。保留卡片、紧凑控件、薄荷色及左上返回；版本显示真实构建，Android 安装文案依据 `design/README.md` 的渠道约定适配，不照搬商店入口。没有修改 Figma 节点，也不声称所有新增错误/系统状态均有逐像素设计稿。

最终普通 Debug APK 独立保存，不覆盖历史二维码、流量或前一次更新预览。CRC、签名、真实版本、嵌入核心摘要、所有原生库和 ZIP 16 KB 对齐通过，见 [android-package.json](android-app-update/android-package.json)。高构建号候选只放在 QA 目录，不作为发布版本交付。

交付文件为 `build/RainLink-0.1.0+4-android-app-update-ui-debug-preview.apk`。普通包与高构建号 QA 包的 294 项原始输入已核对，候选副本仅作构建号及对应生成版本信息调整；锁文件一致。iOS 布局按真实平台 ThemeData 验收后，概览卡片改用现有密度的紧凑列表间距，修复包含安全区时底部多出 6 px 的问题，原零滚动/不遮挡断言保持。

## 复现与剩余范围

- 共享检查：`app/` 下执行 `flutter test --no-pub --machine`、`flutter analyze --no-pub`。
- 原生构建：`python tools/build_android.py --java-home <JDK17> --use-maven-mirror`，包含普通 APK、androidTest、Kotlin 单元及 Lint。
- 候选：`python tools/build_android_update_fixture.py --java-home <JDK17> --attempt <新名称>`，拒绝覆盖已有候选副本。
- 独立 AVD 验收：仅在上述唯一名称的 AVD 运行 `tools/verify_android_update.py --java-home <JDK17> --attempt <名称> --stage provision`，然后依次 safety、permission、cancel、install。provision 会安装、重置该一次性应用；debug 降级仅用于已经完成过升级的此 QA AVD。脚本每次先核验 AVD，禁止用于用户设备。安装前普通 UI 写入测试数据，安装后回读；不要用 `adb install` 替代系统安装确认阶段。
- 布局：`flutter test integration_test/android_update_visual_test.dart -d windows --no-pub`。
- 包检查：`python tools/verify_android_package.py --output docs/verification/android-app-update/android-package.json`。

仍待正式 GitHub 线上发布升级、正式签名、Android 真机和厂商安装器验收。未实现商店更新入口，也没有原生验证 macOS/iOS 应用更新。此阶段未重新构建桌面 Release 或修改公开 Linux TUN 能力；完整平台、发行及全页面实际设备校准继续进行。
