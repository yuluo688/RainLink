# Android 原生网络与移动界面验收

日期：2026-10-17。目标为 Android 10 / API 29 起的 arm64-v8a、x86_64；设备证据来自隔离的 Android 16 / API 36 x86_64 模拟器 `RainLink_QA`，不能替代真机验收。产物为 Debug 签名开发预览。

本地预览包为 `build/RainLink-0.1.0+3-android-debug-preview.apk`。[交付记录](android/preview-evidence.json)校对普通 APK、十项原生验收和包检查的 SHA-256 一致；测试请求客户端只存在于测试 APK。另已启动普通 `MainActivity`，核对[未连接首页](android/preview-home.png)及今日流量位于底部导航上方，未选择节点或导入用户订阅。测试结束已停止应用并[恢复模拟器尺寸、密度和网络开关](android/cleanup-evidence.json)，系统无活动隧道。

## 原生实现

- Kotlin 前台网络服务持有系统隧道及嵌入式 libbox。Activity 销毁不切断服务，断开、取消、撤销授权和服务退出均走资源清理；旧请求的停止回调不能结束较新的连接。
- Flutter、桌面宿主与 Android 共用八协议、规则、代理链和高级设置契约。Android 复用已有 Go 编译器；核心固定为 `1.12.25-rainlink.1`，gomobile、NDK、构建标签及源码校验固定在 `tools/mobile-core.lock.json` 与 `tools/core.lock.json`。
- Android 自动使用系统隧道；首页显示接管状态与代理模式。IPv4、IPv6 均接管，DNS 劫持优先于模式规则。
- 核心套接字经过 `protect` 并绑定物理网络，平台 DNS、UDP / HTTPS DNS 测试和引导查询复用该保护路径。控制接口只监听回环，端口和认证密钥随机生成。
- AES-256-GCM 凭据使用 Android Keystore，随机 IV、节点 ID AAD 及防篡改校验；SQLite 仅保存密文。禁用云端备份与设备迁移，避免复制不能迁移的 Keystore 密文。
- 后台服务仅在内存保留原始加密请求。恢复界面时校对活动目标、节点版本、代理链跳点、规则绑定、模式及实际设置；重启核心继续使用该快照，不重新解析界面当前选择。断开后释放恢复请求。
- 恢复回执先严格解析再比较，兼容原生省略空高级配置；核心启动时设置并回读实际代理模式，并等待 Android 登记同一实际 TUN 后才报告成功。启动失败后只将核心精确的已关闭哨兵视为幂等关闭，其他清理错误仍报告失败。固定 Go 1.25.5 的移动 cgo 导出帧增加指针对齐，修复低内存下读取快照时的桥接崩溃，详见[恢复与桥接修复](android-bridge.md)。
- 原生回执读取实际 TUN 描述符的接口名；编译器不伪造接口名。流量来自核心计数，出口探测与桌面共用；原生日志采用同一脱敏、容量和游标规则。
- 通用设置接入默认关闭的启动自动连接、连接提醒和订阅到期提醒。启动等待原会话恢复，手动断开后返回前台不重连；通知检查真实权限，提醒点击进入对应页面。取消、补偿、原生和界面证据见[自动连接与系统提醒](android-startup-notifications.md)。

## 运行证据

[原生结果](android/native-evidence.json) 记录 APK 摘要、认证代理请求、IPv6、DNS 和双向字节；[instrumentation 输出](android/instrumentation.txt) 对应十项测试。网络五项、文档两项、通知冷启动一项、撤销通知权限一项、切网一项在五个进程中依次验收：

1. Keystore 随机加密、跨实例读取、ID 绑定、防篡改及长度限制。
2. 取消不留下迟到隧道，错误节点 ID 无法解密或启动连接。
3. 独立 shell UID 经实际 TUN 访问 IPv4、IPv6、域名与 DNS；全局 / 直连 / 规则切换、真实计数、前台通知状态、后台传输、Activity 重建、原快照恢复后重连；低内存模式下 12 轮持续传输及快照读取，最后断开并确认无 TUN 残留。
4. 三条真实保持中的传输分别经单条/全部关闭结束；陈旧会话和路径注入不能关闭有效传输，隧道继续可用；日志跨断开保留、游标连续、凭据脱敏、清空后不重放旧事件。
5. 连续三轮占用本地代理端口，触发真实启动失败并确认清理回空闲；随后连接的同一实际 TUN 已在系统登记，独立 UID 经延迟 1.5 秒的代理握手完成真实传输。测试客户端在响应结束前保持写端，避免生产者管道提前结束干扰握手。
6. 系统文件保存器创建 CSV，逐字节核对内容和文件名，再取消第二次保存，确认返回空结果。
7. 拒绝非法导出来源、名称、MIME、请求 ID 和类型；重复请求返回忙碌，无关取消不影响当前请求，选择器打开时销毁 Activity 返回取消。
8. 到期提醒只显示数量，使用 Figma 图标和私密锁屏可见性；真实 PendingIntent 冷启动普通 Flutter 界面并进入分组。
9. 系统实际撤销通知运行时权限后，通知状态必须关闭，到期投递报错、连接可选提醒不出现。另在真实连接测试内验证连接/断开通知，以及停用可选提醒后前台服务通知仍在。
10. 同一活动会话、同一个系统隧道依次经历唯一 Wi-Fi、唯一蜂窝、完全断网及 Wi-Fi 恢复；三次实际传输成功，断网请求失败。再次断网并手动断开后，恢复网络不会迟到重连，网络开关恢复到测试前状态。详见[配置与网络切换验收](android-configuration.md)。

代理、DNS 与目标服务均为本机 fixture。地址使用文档网段，未使用用户真实订阅或 HTTP 账号。授权由 QA 脚本授予，尚未覆盖系统授权对话框的接受与拒绝。八协议共享编译测试通过，不代表 Android 已完成八种远程服务端握手验收。

[完整 APK 检查](android/package-evidence.json) 对每个 Flutter、SQLite、Go 原生库验证 ELF 16 KB 对齐，同时执行 ZIP CRC、`zipalign -P 16`、包名、版本及签名检查。还校对 AAR 摘要，并用固定 NDK 独立复现 AGP 的符号裁剪，确认 APK 的两种架构核心均来自记录的构建。这不能替代在 16 KB 页设备上的实际运行。

最新交付见[预览摘要](android/preview-evidence.json)：10 项原生测试全部通过，主包、实际安装包与完整包检查的摘要一致。普通入口的首页、设置分类及通用详情另有截图及真实返回导航验证。此前软件渲染模拟器的等待超时记录保留；重新启动同一 2 GB AVD 并使用宿主 GPU 后，本轮普通 Debug 入口冷启动回执为 4,583 ms，界面及导航通过。该结果不替代正式启动性能验收。

共享层全量回归为 403 项 Flutter 测试，另有 5 项 Kotlin 授权时序单元测试；此前宿主 Go 回归 94 个通过测试事件、26 个跳过，移动模块 Android arm64 `go vet` 通过，本轮未修改 Go 核心。Android Lint 保持启用。旧 Flutter 插件的 compileSdk 与应用统一；Flutter 3.27 写入的 Windows 属性路径通过构建工具修正，不建立 Lint baseline 或屏蔽规则。

[Flutter 实际核心界面验收](android/flutter-telemetry-evidence.json) 在本机 HTTP 流上验证界面关闭、SQLite 日志采集、断开后读取、两类 CSV 实际写入和确认清空。该流显式使用本地代理；独立 UID 经 TUN 的证据来自上面的原生测试。两类证据及导出范围见 [Android 遥测](android-telemetry.md)。

[代理链、规则与在线配置验收](android-configuration.md)通过实际移动编辑器保存双跳，再从概览连接，验证修改选择不影响活动路径、重连反向链、规则链与三模式、在线高级配置拒绝及恢复、端口冲突后恢复原连接。9 次响应及目标计数逐一核对；每个请求的两跳记录与后台探测分开，不能用连接数量冒充实际路径。

连接、日志、流量及高级配置导出使用系统文件保存器选择位置；实际写入完成后才返回文档 URI。系统保存与 Flutter 私有导出器的测试边界分别记录，见[系统文件保存](android-documents.md)。

## 视觉核对

本次从连接中的 RainLink Figma 文件重新导出[首页](android/reference-home.png)、[节点](android/reference-nodes.png)与[设置](android/reference-settings.png)。首页改为独立的大连接按钮、连接目标、系统接管、三段模式、出口、上传下载和今日用量；标准 393×852 包含安全区时完整显示，大字或窄屏支持滚动。

[Android 原生渲染结果](android/ui/evidence.json) 包含五个主页面与连接、日志、通用设置的深浅主题，共 16 张截图。均为隔离 UI fixture，IP、节点、流量不代表真实网络，与实际核心的两张截图和原生网络测试分别记录。本轮还验证[启动自动连接与原会话保留](android/flutter-startup-evidence.json)，并新导出[当前 Figma 移动设置](reference/android-mobile-settings-current.png)。

- [首页 · 深色](android/ui/overview-dark-fixture.png) / [浅色](android/ui/overview-light-fixture.png)
- [节点](android/ui/nodes-dark-fixture.png)、[分组](android/ui/groups-dark-fixture.png)、[流量](android/ui/traffic-dark-fixture.png)、[设置](android/ui/settings-dark-fixture.png)

44 个图标、品牌与国家 SVG 与当前 Figma 原生导出逐字节一致，见[完整图标摘要](android/icon-full-evidence.json)；[本轮复核](android/icon-baseline-recheck.json)确认应用资产仍与该导出基准一致，没有重新读取云端修订。品牌生成检查覆盖 27 个 PNG 和 9 尺寸 ICO，Android 通知图标沿用并校对 Figma 链路矢量路径。系统状态栏、安全区以及 Android / iOS 的授权用语按平台适配；设置保留用户要求的六分类。尚未对所有弹窗、设置详情和不同厂商设备逐一完成视觉校准。

移动订阅行将节点数量移到名称旁，流量与完整到期日期按可用宽度换行，避免日期被省略号隐藏。密度回归使用应用实际字体检查 393 宽紧凑行不超过 80，以及 320 宽大字下两个字段完整位于卡片内；不以缩小字体换取单行。

## 复现

需 Flutter 3.27.4、Java 17、Go 1.25.5、Android SDK 和 NDK 27.0.12077973。SDK / Flutter 路径从本机 `app/android/local.properties` 读取，不提交本机路径或 Debug 密钥。

```powershell
# 仓库根目录，JAVA_HOME 指向本机 Java 17。
python tools/setup_mobile_core.py --java-home $env:JAVA_HOME
python tools/build_android.py --java-home $env:JAVA_HOME --use-maven-mirror
python tools/verify_android.py --serial emulator-5580
python tools/verify_android_package.py
```

原生 fixture 工具只接受名称为 `RainLink_QA` 的 AVD；安装两份 QA APK，签名不兼容时重装该 AVD 内旧 QA 包，结束时强制停止 QA 应用释放隧道。

界面及实际核心验收从仓库根目录执行，`FLUTTER_ROOT` 指向 Flutter SDK；需要上面构建的两份 QA APK：

```powershell
$env:ORG_GRADLE_PROJECT_useMavenMirror='true'
python tools/verify_android.py --serial emulator-5580 --ui --flutter-root $env:FLUTTER_ROOT
```

截图使用模拟器 1179×2556、480 dpi，对应 393×852 逻辑像素。脚本仅在命名 QA AVD 安装测试包并预先授予系统网络及通知权限，不覆盖真实授权弹窗。Flutter 测试退出会移除应用，重跑也须执行脚本。`flutter drive` 临时替换测试入口；其后运行 `tools/build_android.py` 恢复 `lib/main.dart`，再执行原生及包检查，不能把视觉测试 APK 当作应用预览包。

## 未完成范围

真机和厂商后台限制、真实授权接受 / 拒绝、真实订阅及八协议远端、真机 Wi-Fi / 蜂窝切换、长时间和 16 KB 页设备仍待验收。系统分享、关闭应用后的定时唤醒和移动分发签名仍未接入；自动连接、可选通知、配置流程及切网已有模拟器验收。macOS、Linux 宿主与 iOS 网络扩展仍未完成。
