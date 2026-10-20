# 扫码导入与分享链接

日期：2026-10-20。本阶段补齐当前 Figma 添加弹窗中的扫码入口，覆盖代码、表单保存、Android 相机和布局验收。五平台完整目标仍在进行，历史包与记录保持原样。

## 使用行为

- 移动端在“分组 → 添加订阅”或“节点 → 添加节点”的添加弹窗中点击“扫码导入”。仅此时申请相机权限，扫码结束、返回或后台暂停时释放相机。
- 识别订阅或单个节点后，返回对应页签并预填表单。扫码本身不下载、不写库、不连接；继续点击“导入订阅”或“保存节点”才提交。
- 订阅自动成为独立分组，自动识别名称并保存服务商提供的用量、总额度和到期时间；手动节点保存到“未分组”。编辑已有节点不提供替换身份的扫码/分享链接入口。
- 共享现有解析与校验：HTTP/HTTPS、SOCKS5、Shadowsocks、VLESS、VMess、Trojan、Hysteria2、TUIC；保留 TLS、Reality、传输和协议专用参数。修复 Dart URI 规范化移除 `:80` / `:443` 后，HTTP 分享链接被误判缺少端口的问题。
- 没有认证、路径或参数的 `http://host:port` 可能表示订阅，也可能表示单个代理，明确弹窗选择用途；取消保留原表单。
- 桌面端使用“粘贴分享链接”预填单个节点。扫码仅在 Android/iOS 提供，相机拒绝、不可用或启动超时均可返回粘贴；没有自动读取剪贴板。
- 多码、重复码、无效内容、超长输入及原生错误有安全中文状态，不在错误或日志中回显二维码、密码或 token。返回箭头在左上角，最小点击区域为 44×44。

## Android 原生验收

使用普通 `main.dart` Debug APK，在单独创建的 `RainLink_QR_QA` API 36 x86_64 AVD 中运行。CameraX/ML Kit 实际读取 virtualscene 摄像头帧，向场景墙面放置测试二维码；没有使用 Dart 扫描结果回调 fixture 代替相机识别，也没有访问用户订阅、数据库或设备。

最终六项原生流程通过，见 [evidence.json](qr-import/android/evidence.json) 和 [执行日志](qr-import/logs/native-qa.log)：

1. 原生权限弹窗选择拒绝，显示中文拒绝状态，并返回原添加表单。
2. 授权后实际相机识别无效二维码，显示固定安全提示。
3. 进入后台后 CAMERA AppOp 不再运行，返回前台后恢复取景。
4. 实际 HTTP QR 识别后，确认前 SQLite 节点数为零；明确保存后，节点端口 80、所属“未分组”及加密凭据均回读正确。
5. 实际订阅 QR 识别后本地服务请求数为零；明确导入后恰好请求一次，自动分组名 `QR 测试订阅`、上传 1,024 B、下载 4,096 B、总量 1 GiB、到期时间戳 1,930,000,000 正确，组内拥有一个导入节点。
6. 停止并重启普通应用后，分组、用量、到期仍正确显示；最终应用停止，相机 AppOp 不再运行。

截图分别记录[真实取景](qr-import/android/camera-live.png)、[节点预填](qr-import/android/node-preview.png)、[订阅预填](qr-import/android/subscription-preview.png)和[重启回读](qr-import/android/reopened.png)。这些是模拟器原生相机证据，不能当作 Android 真机或 iOS 验收。

初次自动化未完成，原因是脚本按子串点中了说明文字，以及隔离设备的调试授权弹窗覆盖页面。脚本现仅点击启用的可点击控件、优先精确标签，并在 accessibility dump 临时无根节点时重试，禁止读取旧 XML。只授权本次 QA AVD，最终完整重跑通过；未放宽产品断言。早期失败画面留在 `build/qa/qr-import/harness-diagnostics/`。

## 自动检查与设计核对

| 检查 | 最终结果与范围 |
| --- | --- |
| Flutter 全量 | 522 项通过，包含 40 项扫码解析、相机生命周期及 UI 回归；静态分析无问题；本阶段 14 个 Dart 文件格式检查无变化 |
| 八协议表单 | 各协议预填后明确保存，真实内存 SQLite 回读全部字段、TLS/协议参数、未分组归属及凭据；订阅组名和 metadata 亦回读 |
| 异常与取消 | 重复/多码、无效/超长、HTTP 用途两种选择/取消、权限拒绝、后台恢复、迟到权限结果、超时后释放、关闭失败、编辑保护与无相机粘贴回退 |
| Windows 原生渲染 | 32 张 fixture 截图，1440×900、960×640、393×852、320×740@1.3，深浅主题；溢出/点击断言通过。相机画面是明确 fixture，不能证明硬件扫码 |
| Android 构建 | 普通 Debug/测试 APK、5 项 Kotlin 单元和 Lint 通过；Lint 0 错误、4 条警告（OldTargetApi、GradleDependency、ObsoleteSdkInt、UseKtx） |
| Android 包 | 最终 APK 的签名、CRC、嵌入核心一致、全部原生库及 ZIP 16 KB 对齐通过，包含 ML Kit 的 `libbarhopper_v3.so`；见[包检查](qr-import/android-package.json) |
| Apple 平台 | iOS 增加中文相机用途说明，macOS 自动生成插件注册已更新；没有 Mac，未执行 Swift/Xcode/相机权限或原生构建 |

计数、源日志摘要和最终构建结果见 [tests.json](qr-import/tests.json)。本阶段没有修改 Go、协议或 Linux 公开 TUN 能力，`capabilities.tun` 继续为 false。

本轮已从当前 Figma 读取移动添加页 `2:23573`，导出[参考图](qr-import/reference/mobile-import.png)，新增流程使用的 `qr`、`back`、`copy` 三个图标与 Figma 原生 SVG 导出逐字节一致，见[图标摘要](qr-import/reference/icons.json)。前阶段完整 44 个图标证据保留在[流量归属](traffic-accounting/figma-assets.json)，本轮只重验使用的三个。

布局保留既有添加弹窗、分段页签、薄荷色按钮和紧凑表单；扫码状态页补齐设计稿尚未展开的拒绝/错误/暂停状态。32 张截图在 `qr-import/visual/`。手动节点字段较多时表单主体允许滚动，保存操作保持可达。

## 依赖与复现

锁定 `mobile_scanner: 7.0.1`，沿用 Flutter 3.29.3 / Dart 3.7.2，Dart SDK 约束同步为 `^3.7.0`。Android 使用 CameraX 1.4.2 / bundled ML Kit 17.3.0，识别模型随 APK 提供；相机硬件声明 `required=false`。平台适配器明确持有监听及 native view，串行启停/释放，等待迟到的系统权限结果后再释放给下一次扫描。

- 自动回归：在 `app/` 执行 `flutter test --no-pub --machine`、`flutter analyze --no-pub`。
- 视觉：`flutter test integration_test/qr_import_visual_test.dart -d windows --no-pub`，使用 fixture，不访问生产数据库。
- 包检查：`python tools/verify_android_package.py --output docs/verification/qr-import/android-package.json`。
- 原生：先准备唯一名为 `RainLink_QR_QA` 的一次性 AVD，后置摄像头设为 virtualscene，console 5584 / transport 5585，使用独立 ADB server 5047。安装 test-only `qrcode==8.2` 到 `build/qa/qr-import/python` 后执行 `python tools/verify_qr_import.py`。脚本在安装、清数据和权限操作前校验 AVD 名和 APK 包名；只对该一次性应用清数据，不可对用户设备运行。局域订阅只提供虚构 fixture，凭据和 QR 原文不进入日志。

## 产物与剩余范围

独立保留 `build/RainLink-0.1.0+4-android-qr-import-debug-preview.apk`，明确为 Debug 签名的双 ABI 预览包；摘要见 [artifacts.json](qr-import/artifacts.json)，与实际原生验收 APK 一致。没有覆盖历史流量归属包。

尚需 Android 真机相机、不同厂商授权/后台及 iOS 原生验收；Windows/Linux/macOS 没有开放扫码按钮，桌面可粘贴分享链接。本阶段没有重新生成桌面 Release 包，也不把它计为五平台完整交付；不提交、推送或发布。
