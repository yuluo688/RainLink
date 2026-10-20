# Android 实际流量与应用归属续验

日期：2026-10-20。本阶段补 Android 的运行证据，复用既有流量统计、排行榜和移动页面，没有新增产品页面或改变统计口径。macOS/iOS 原生、真机、正式分发与完整五平台目标继续推进；公开 Linux TUN 能力仍关闭。

## 已验证的行为

专用 `RainLink_Traffic_QA` API 36 x86_64 AVD 运行真实 Android 网络服务与嵌入核心，使用私有 ADB 5047、console 5592 / transport 5593。节点、认证代理、HTTP 源均为本地测试数据，没有导入用户订阅或读取用户数据库。

独立的 shell UID 客户端通过实际系统隧道请求：全局、直连、规则三模式各 12 次，同一会话完成 36 次请求。服务端独立确认 36 份完整正文回执，代理观察到其中 24 次，直连为其余 12 次。全部响应已结束后，核心累计用量仍包含这些流量，Android 实际识别到 `com.android.shell`。

核心 → Flutter Controller → SQLite schema 8 → 流量页面 → CSV 已贯通。出站与应用排行是同一总量的两个独立分区，各自上下行合计与总量一致；重复采样不增加用量。断开连接、关闭并重开数据库、重新挂载实际应用页面后，记录和排行榜仍可读取。外部脚本复制关闭后的 SQLite，另外执行完整性、schema、时段总量和两个来源分区的 SQL 核对。

最终结果与每个验收输入的摘要见 [native-evidence.json](android-traffic-accounting/verified/native-evidence.json)，应用内读数和五张截图索引见 [flutter-evidence.json](android-traffic-accounting/verified/flutter-evidence.json)。上传包含 HTTP 请求及测试完成回执，下载包含 HTTP 头与正文，不能与纯正文大小直接画等号。

## 测试实现与诊断

- `app/integration_test/android_traffic_accounting_test.dart` 使用真实平台通道、Controller、SQLite 和页面。测试专用文件握手仅存在于独立测试入口，产品通道没有增加测试接口。
- `app/test_driver/android_traffic_accounting_driver.dart` 校验所有必要断言后保存证据；截图不混用桌面 runner。
- `tools/verify_android_traffic.py` 在任何安装、授权或写入之前检查唯一 AVD 名称，使用一次性运行标识和新的输出目录，拒绝覆盖旧成功报告。真实请求由其他 UID 发起，避免 RainLink 自身在隧道排除名单内导致假通过。
- 原生 `TunnelRequest` 测试客户端先逐字节验证完整 HTTP 正文，再返回 SHA-256 小回执；服务端等收到正文完成标记后才关闭连接。原来的 `/probe`、`/hold` 等流程保持既有行为。

初次验收检出了 ADB shell 改写换行，随后客户端内部断言又检出测试源立即关闭时的尾部短读；后者在没有运行核心的模拟器直连中也能重现，不能只归因于 ADB。现保留原始字节通道、客户端完整正文断言及服务端回执三个独立检查，没有通过重试丢弃失败请求或放宽长度来计成功。专用模拟器的首次启动还发现 PATH 中旧 ADB 和当前 SDK 密钥目录不一致，修复后仅重启私有测试服务，默认 ADB 与用户设备未改。

## 设计核对

当前 Figma RainLink 文件 `unsaved-mvfj9942-5y6aivnm` 的移动流量 `2:23007` 与桌面流量 `2:19136` 已重新原生导出，[移动参考](android-traffic-accounting/reference/mobile-traffic.png)和[桌面参考](android-traffic-accounting/reference/desktop-traffic.png)保留。导航、导出和品牌使用的七个 SVG 与当前 Figma 导出逐字节一致，见 [icons.json](android-traffic-accounting/reference/icons.json)。未修改设计节点。

五张实际 Android Flutter 渲染截图覆盖深浅主题、出站/应用排行和数据库重开：

- [深色应用排行](android-traffic-accounting/verified/applications-dark.png)
- [深色出站排行](android-traffic-accounting/verified/outbounds-dark.png)
- [浅色出站排行](android-traffic-accounting/verified/outbounds-light.png)
- [浅色应用排行](android-traffic-accounting/verified/applications-light.png)
- [重开后应用排行](android-traffic-accounting/verified/reopened-applications-light.png)

截图为真实 Android renderer 的 Flutter 边界，不包含系统状态栏合成层；部分画面已滚动到排行。保留薄荷/紫色曲线、圆角卡片、导航和细进度条。运行图表表示真实 15 分钟用量，设计稿是示意 MB/s；运行排行展示真实包名，设计稿是示意应用分类。这些差异继续明确保留，不声称全页面逐像素一致。

[Figma / 实际 Android 对照总览](android-traffic-accounting/visual-contact-sheet.png)便于集中查看上述差异。

## 检查与产物范围

本阶段产品源码未改变，新增代码限验收入口、测试客户端和本地工具。[输入比较](android-traffic-accounting/product-inputs.json)核对上一 Android 更新阶段的 292 项产品输入一致，另外明确排除生成的 `android/local.properties` 与本次修改的原生测试客户端。没有重新发布、提交或推送。

普通预览包继续使用 [Android 更新阶段](android-app-update.md)的 `build/RainLink-0.1.0+4-android-app-update-ui-debug-preview.apk`，它包含本次验收的生产流量逻辑。Flutter drive 构建的是专用测试入口，不能作为普通应用分发。前一阶段的 539 项共享测试、44 张布局及包检查仍按原报告保留，本阶段新增运行验收与最终静态检查单独记录。

最终[检查摘要](android-traffic-accounting/tests.json)及 [logs](android-traffic-accounting/logs/)保留每项结果：

| 检查 | 本阶段结果 |
| --- | --- |
| Android 实际流量集成 | 1 个完整场景、36 次实际响应与 36 份服务端正文回执通过 |
| 原有原生网络回归 | `AndroidCoreTest` 5 项通过，含 IPv6、后台恢复、取消和真实连接关闭；见[基线结果](android-traffic-accounting/baseline/evidence.json)与[原始 JUnit 输出](android-traffic-accounting/baseline/instrumentation.txt) |
| 普通 Debug / androidTest 构建 | 通过；5 项 Kotlin 单元通过；Lint 0 错误、7 条警告，未屏蔽规则 |
| Flutter 静态分析与格式 | 全应用分析无问题；两个新增 Dart 文件最终格式检查无变化 |
| Python 语法 | 两个修改/新增工具通过 |
| 实际渲染与当前资源 | 5 张 Android 截图、7 个 SVG 字节一致 |
| 输入与产物 | 验收源码摘要、复制的 SQLite/CSV、普通预览 APK 摘要及报告链接核对通过 |

测试完毕后已核对名称并正常退出该 AVD，断开其残留 TCP transport，确认没有其他设备后关闭私有 ADB 5047。AVD 磁盘和全部证据保留，见[清理记录](android-traffic-accounting/cleanup.json)。先前的脚本诊断与首次成功结果保存在 `build/qa/android-traffic-accounting/harness-diagnostics/`，没有覆盖最终结果。

## 复现

先创建且仅使用 `RainLink_Traffic_QA`，启用独立 ADB 5047 并连接其 transport 5593。使用与模拟器一致的 SDK ADB 和密钥目录，避免调用 PATH 内其他版本。普通 APK 与 native androidTest APK 通过 `tools/build_android.py --java-home <JDK17> --use-maven-mirror` 构建。

运行 `python tools/verify_android_traffic.py --java-home <JDK17> --apk <普通 main.dart Debug APK> --attempt <新名称>`。脚本要求普通入口安装包，防止把上一轮 Flutter drive 测试 APK 当成产品；新的输出目录必须不存在。结束后仅关闭该 AVD 和确认空闲的私有 ADB，保留测试磁盘及记录。

本阶段只证明该 API 36 x86_64 AVD、shell UID 和本地 HTTP 路径。第三方应用包可见性、不同 Android 版本/厂商、真机网络及后台范围不能从这里外推；Android UDP 的历史网络验收与 Windows/Linux 统计验收仍以各自报告为准。Mac 不可用的原生范围继续保留，未计为完成。
