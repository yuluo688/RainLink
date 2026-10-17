# Android 自动连接与系统提醒

日期：2026-10-17。普通入口为 `lib/main.dart`；本地预览包沿用 `build/RainLink-0.1.0+3-android-debug-preview.apk`，仅供 Debug 签名开发预览。交付摘要以 [preview-evidence.json](android/preview-evidence.json) 为准。

## 使用与行为

进入「设置 → 通用」：

- 「启动时自动连接」默认关闭。开启后，打开应用时使用上次选择和已保存的代理模式连接；Android 自动使用系统隧道。已有后台连接优先恢复，当前选择不会替换其原始节点或代理链。
- 「连接状态通知」与「订阅到期提醒」分别开关，默认关闭。开启时检查系统授权及对应通知通道；未允许时显示错误，不将开关保存成开启。「系统设置」可打开 RainLink 的 Android 通知设置。
- 连接状态提醒由原生服务发送，包含连接、断开及脱敏的异常说明。关闭可选提醒只取消该类提醒，连接中的前台服务通知继续保留。
- 到期提醒只在应用前台运行时检查：到期前 3 天内及到期时各提醒一次。仅显示数量，续期按新到期时间重新判断；无到期信息不提醒。SQLite 记录正常重开的去重信息，通知或记录失败可重试。
- 点击连接提醒进入首页，点击到期提醒进入分组。冷启动和已打开的 Activity 均接入同一白名单路由。

自动连接只在一次 UI 启动中尝试一次；手动断开后返回前台不会重新连接。等待期间关闭界面、取消连接、离开前台或停用自动连接，都会阻止迟到启动。本功能不注册开机接收器、不在关闭应用后定时唤醒。

## 一致性与取消

通用设置通过同一个串行队列同步原生偏好与 SQLite。磁盘保存或原生确认失败时恢复原值；恢复失败明确提示用户检查。启动同步也经过该队列，避免覆盖用户刚保存的通知选择。桌面继续验证通知对托盘的依赖，移动端不需要托盘。

Android 授权对话框不能由 Dart 超时操作直接关闭。因此取消只释放旧调用方，保留系统对话框占用，直到真实回调到达；在此之前拒绝新的授权和连接申请。Activity 重建保存对话框状态，防止旧结果完成新的请求。原生启动授权失败返回安全错误。

## 验收记录

- 402 项 Flutter 测试通过，静态分析无问题。覆盖启动等待、已有会话优先、取消/前后台边界、设置补偿、启动同步与用户保存竞争、拒绝授权不误开开关、通知通道路由及 320 宽大字布局。数据库异步链在启动及清理错误报告前转换为 VM 堆栈，保留原异常与帧，避免错误显示再次抛错而中断清理；另有两项回归。
- 5 项 Kotlin 单元测试通过，覆盖超时后的迟到结果、无关取消、启动失败、Activity 释放及重建。构建脚本执行 `:app:testDebugUnitTest`，Android Lint 保持启用。
- [真实自动连接结果](android/flutter-startup-evidence.json)：实际 Android bridge、Keystore 与 libbox，在独立内存 SQLite 保存选择和模式，自动建立 TUN，并经显式本地代理完成两次真实 localhost 请求。重建 UI 容器时刻意选择另一节点，确认原会话及目标保持；手动断开再回前台后，UI 和原生服务都为空闲。
- [原生系统结果](android/native-evidence.json)及[instrumentation 输出](android/instrumentation.txt)的 9 项测试在 4 个独立进程中全部通过。包含实际连接/断开提醒、关闭可选提醒后仍保留前台通知、系统撤销通知权限时拒绝到期投递，以及实际到期通知 PendingIntent 冷启动并打开 Flutter 分组页。认证代理完成 25 次实际请求，覆盖 IPv6、37 次 DNS 查询、3 条保持传输的关闭及 3 轮延迟握手恢复。网络、Keystore、导出及启动失败恢复一并回归。
- [界面记录](android/ui/evidence.json)有 16 张 Android 深浅主题 fixture，包括新增[通用深色](android/ui/settings-general-dark-fixture.png)与[浅色](android/ui/settings-general-light-fixture.png)。fixture 的 IP、节点、用量和系统权限状态不代表用户真实数据。

真实核心验收中的 UI 重建发生在同一 Activity 内；已有的原生网络测试另覆盖 Activity 重建，但不等于操作系统杀进程后自动恢复。系统权限由命名 QA AVD 的脚本准备；拒绝测试在撤销真实通知运行时权限后启动独立测试进程，以避免 Android 撤权终止正在运行的验收。尚未验收人手接受/拒绝系统授权弹窗及厂商通知表现。

同一 2 GB / API 36 模拟器进程连续执行全部生命周期、网络及文件测试时，曾在文件保存器切换期间发生焦点无响应，见[失败记录](android/long-sequence-failure.json)与[原始输出](android/long-sequence-instrumentation.txt)。当时系统另记录 Google 文档启动无响应及明显内存、I/O 压力；文件两项独立进程重跑通过。最终验收按网络、文档、通知冷启动、撤权四个进程运行，保持全部断言。此结果不证明长序列反复创建 Flutter Activity 的压力问题已解决，真机及长期生命周期压力仍待验证。

原生测试还等待普通 Flutter 启动同步的真实完成回执，再修改原生通知偏好或打开系统文件保存器。这样不会在应用仍恢复 SQLite 设置时由测试直接写入另一组开关；Activity 重建也等待新实例完成同步。

最终预览包已更新。[交付摘要](android/preview-evidence.json)、原生验收、完整包检查与模拟器中实际安装 APK 的 SHA-256 一致，为 `fb254a71b53c1f9879512185f692da98c0b02aa031a1b7d8b4decb4bdae94436`。另以普通 `main.dart` 入口查看[首页](android/preview-home.png)、[设置分类](android/preview-settings.png)与[通用详情](android/preview-settings-general.png)：首页今日流量在底部导航上方、六分类可见、三个开关默认关闭，左上角返回可实际回到设置分类。测试专用请求客户端只存在于测试 APK。Android Lint 为 0 错误、4 项警告；250 个 Dart 文件格式检查无改动。

上述 2 GB / API 36 模拟器的 Debug 普通冷启动两次超过 `am start -W` 的等待时间，随后界面约 15 秒内显示，导航和设置检查通过；原始启动输出保留在[普通界面记录](android/preview-ui-observation.json)。该现象尚未归因，也未完成启动性能验收，不能据此推断正式 AOT 包或真机表现。

## Figma 核对

当前连接的 RainLink 文件为 `unsaved-mva99nf3-128z4u3c`。[移动设置参考](reference/android-mobile-settings-current.png)从节点 `2:23130` 新导出。保留用户要求的六分类详情与左上角返回；自动连接与提醒放在通用详情，连接提醒和到期提醒分别控制。通用页缩短长说明，标准 393×852 完整显示，窄屏或大字允许自然增长。

[44 个 SVG 核对](android/icon-full-evidence.json)记录从当前 Figma 原生重新导出、逐字节一致的图标、品牌和国家图标；Android 通知矢量路径与 Figma 的链路 SVG 一致。生成器另核对 27 个原生 PNG 和 9 尺寸 ICO。以上证明资源来源及已查看页面，尚不能声称全部弹窗和跨平台画面已逐像素一致。

真机通知授权、Wi-Fi / 蜂窝切换、真实订阅远端和移动正式签名分发仍待验收；macOS、Linux 宿主与 iOS 网络扩展仍未完成。
