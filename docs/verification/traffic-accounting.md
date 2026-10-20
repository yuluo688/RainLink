# 实际出站与应用流量归属

日期：2026-10-20。范围是本轮流量归属功能及关联布局、核心和预览包，不表示五个平台已完整交付。前阶段报告保留其当时的版本、哈希和验收边界。

后续 Android 实际运行验收已补齐，见[Android 流量与应用归属](android-traffic-accounting.md)：真实三模式请求、已结束连接、shell 包名、SQLite/CSV、去重及重开通过。下文保留本报告发布时 Android 仅构建检查的原始范围。

## 已完成行为

- 核心在 TCP/UDP 的真实字节回调累计，每条流固定其实际出站与应用计数器，结束连接仍保留。规则出站、代理链和在线模式切换不再按当前选择推测归属。
- 宿主冻结节点/链身份，按实际节点统计分组规则。应用只保留进程 basename 或 Android package，公共 ID 为名称摘要，不保存完整路径、PID、目标地址或凭据。
- 出站与应用是同一用量的两个独立分区，各自等于上下行总计；页面和 CSV 都不能把两个排行相加。
- SQLite schema 8 在同一事务写入日汇总、15 分钟 bucket、两个归属分区和来源检查点。重复/迟到样本不重复入账，时钟回拨不冻结统计；来源缺失/回退、非法 epoch、溢出或分区不守恒整笔回滚。
- 旧版聚合迁移保留历史，第一次精确采样没有可靠来源基线的间隔归为未知，后续再记录来源增量。旧日汇总在两个排行分别补未知，不伪造历史曲线。
- 流量页原排行卡片内切换“出站 / 应用”，默认应用。960×640 小窗口并排放置曲线与排行，1440×900 保留上下卡片；393×852 与 320×740 大字号保留独立移动布局。
- 桌面 CMake 排除 Flutter 测试专用 `native_assets.json`，清理旧输出中的同名副本，避免测试元数据及绝对开发路径进入预览包；Windows 打包边界仍拒绝此文件。

## 实际传输证据

Windows 本机与隔离 Linux 普通用户分别运行 `app/integration_test/desktop_traffic_accounting_test.dart`，使用实际核心、私有 IPC、SessionController、文件 SQLite 与 CSV。

每端均完成全局/直连/规则三模式共 36 次本地 HTTP 请求，其中 12 次经过隔离 HTTP 节点。全部连接结束后仍记录上传 4,392 字节、下载 1,187,388 字节，其中响应正文 1,179,648 字节。两种排行分别守恒；重复采样、数据库关闭重开和导出回读通过。Windows 识别到 `rainlink-ui.exe`，Linux 识别到 `rainlink`。结果分别为 [Windows](traffic-accounting/windows-evidence.json)、[Linux](traffic-accounting/linux-evidence.json)，CSV 同目录。没有打开用户数据库，也未申请系统代理或 TUN。

更底层的真实核心回归还包括：保持一条旧全局 TCP 流后切模式，确认后半段仍归原出站；1,050 个不轮询的短连接，超过上游默认关闭连接保留数后计数仍完整；真实 SOCKS UDP；全部关闭后与核心总计对比；新核心 epoch 变化和清零。Windows 与 Linux 均出现非零的实际应用归属。此类本地流量证据不代表远端机场服务质量。

新端到端夹具最初未通过，原因在于自写 HTTP 代理夹具。改为复用已有、限回环的 CONNECT 夹具后通过；Linux 新网络命名空间也先启用自己的回环接口再执行。没有为通过测试放宽产品校验或更换真实接口为假数据。

## 自动检查与平台范围

计数与日志摘要见 [tests.json](traffic-accounting/tests.json)，原始日志摘要在同目录 `logs/`。

| 检查 | 本轮结果与边界 |
| --- | --- |
| Flutter 最终全量 | 482 项通过；静态分析无问题，点击不到目标的警告为 0 |
| Windows Go | 全量 200 个通过事件、3 个显式接管测试跳过，包含子测试；随后新增移动契约测试单独通过；`go vet` 通过 |
| Linux Go | 实际 Linux ELF 运行 accounting / 分区验证 / 移动公共契约及真实 TCP/UDP 通过；Linux `vet` 交叉检查通过 |
| Windows/Linux Flutter 集成 | 两端实际核心 → SQLite → CSV 通过；Linux 额外通过 10 项流量回归 |
| Android | 双 ABI 新 AAR、普通 Debug APK/测试 APK 构建，5 项 Kotlin 单元通过；Lint 0 错误、4 警告；包内核心、签名、CRC 与所有 native libs/ZIP 16 KB 对齐通过。本轮未安装到设备 |
| macOS | Intel/Apple Silicon 核心、宿主交叉编译与 Go vet 通过；无 Mac，没有 Swift、Xcode、Keychain 或系统原生运行证据 |
| Python | 原有相关 23 项中 21 通过、2 个 POSIX 场景跳过；最后新增打包回归后 Windows 打包 5 项通过 |
| 性能边界 | 只针对额外 atomic counter 热路径：6.435–6.720 ns/op、0 B/op、0 allocs/op；不代表整个应用、进程查找或网络吞吐性能 |

核心版本为 Windows/macOS/Android `1.12.25-rainlink.3`、Linux `1.12.25-rainlink.4`。核心构建前运行 TLS、流量和 API 扩展测试，对应源码和说明包含在源码交付物。接口契约见 [HOST_PROTOCOL](../HOST_PROTOCOL.md)。

## 视觉与设计核对

实时读取 RainLink Figma 的桌面流量 `2:19136`、移动流量 `2:23007`，并从当前设计系统重导出 44 个 SVG，与运行资源 44/44 字节一致，见 [图标证据](traffic-accounting/figma-assets.json)。没有修改设计节点。

两套真实桌面 runner 各输出 24 张 fixture 图：1440×900、960×640、393×852、320×740@1.3；深浅主题；初始/出站/应用。截图位于 `traffic-accounting/visual/windows` 和 `visual/linux`。检查覆盖排行切换、窄屏/大字、截断、点击区域及明暗主题；960×640 新增断言保证 fixture 的最后一条排行可直接看到。移动尺寸是桌面 runner 渲染，不能视为 Android/iOS 系统适配已验收。

布局保留设计稿的薄荷色/紫色双曲线、圆角卡片与细进度条。运行时显示实际应用 basename，图表按持久化的 15 分钟字节用量显示单位，而设计稿使用示意应用分类和 MB/s；这两处差异明确保留。截图中的示例排行和曲线不是在线公网测速结果。

## 预览产物

版本仍为 `0.1.0+4`，使用独立文件名保留旧包。本轮包与输入摘要记录在同目录，不能直接套用历史包摘要：

- Windows：`build/RainLink-windows-x64-traffic-accounting-preview.zip`，Release 引擎、锁定核心、宿主、启动器/图标、ZIP CRC 与逐文件摘要核对通过，见 [Windows 包](traffic-accounting/windows-package.json)。Windows 实际传输集成使用原生 Debug runner，没有用普通 Release 入口打开用户数据。
- Linux：`build/RainLink-linux-x64-traffic-accounting-preview.tar.xz`，Release 引擎、核心/宿主、源码、运行资源、权限及逐文件摘要核对，见 [Linux 包](traffic-accounting/linux-package.json)。公开 `capabilities.tun=false`。
- Android：`build/RainLink-0.1.0+4-android-traffic-accounting-debug-preview.apk`，明确为 Android Debug 签名，包检查见 [Android 包](traffic-accounting/android-package.json)。

三份产物复制到 Windows 工作区后再次核对摘要，见 [artifacts.json](traffic-accounting/artifacts.json)。Linux 的 625 项源/核心输入在 Windows 与隔离构建副本逐项匹配，见 [输入核对](traffic-accounting/linux-source-verification.json)。

Linux 最终 tar 在带空格的临时安装路径解压，逐文件重新核对 manifest 后实际启动。首次创建 schema 8、正常退出，再把本地集成 CSV 的数据写入这份隔离 fixture 数据库，第二次启动实际 Release 页面并切换排行；两次退出码均为 0，`G_DEBUG=fatal-warnings` 下没有 GTK critical/warning，公开 TUN 仍为 false。截图是已存 CSV 数据的回放，不是第二轮在线传输，见 [Release 结果](traffic-accounting/linux-release/result.json)。原有 Flutter `The implicit view cannot be removed` 退出诊断仍出现，原始日志保留。

## 复现入口

先通过 `tools/dev.ps1 prepare` 或 Linux `tools/dev.sh` 准备匹配的旁置宿主与核心，再运行 `app/integration_test/desktop_traffic_accounting_test.dart`，传入 `RAINLINK_HOST_PATH`。Windows 必须将 `LOCALAPPDATA` 指向包含 `/traffic-accounting/isolated-` 的一次性目录；Linux 使用同样受限的 `XDG_DATA_HOME`，同时隔离 XDG 配置/状态目录，并确保当前命名空间的回环接口可用。测试会在网络请求前断言隔离目录。

视觉入口为 `app/integration_test/traffic_accounting_visual_test.dart`，通过 `RAINLINK_VISUAL_OUTPUT` 选择截图目录。实际流量证据可通过 `RAINLINK_EVIDENCE_OUTPUT` 选择目录。两者均使用 `flutter test <入口> -d windows|linux --no-pub --dart-define=...`，不要和同一平台的 Release 构建并发运行。

## 仍保留的限制

应用名不等于用户友好的应用分类；basename 相同的进程合并，无法识别的部分显示“未识别应用”。核心最多保留 2,048 个出站/应用组合及 127 个已识别应用，超限进入未知并保留字节总计。Android 的实际 package 识别、真机后台与授权仍需设备验证；iOS 没有接入 Network Extension，也不承诺其他应用的完整归属。

未采样间隔按下次持久采样时的本地日历日/时段记账；突然退出前没有采集的字节无法追回。核心计数器与 `ResetStatistic` 独立，正常断开尽力保存最后样本。接口或存储失败会给出统计未保存状态，不把失败伪装为当前节点的成功归属。

macOS/iOS 原生、正式签名/分发、完整桌面环境和其他网络场景继续按实现清单推进；本轮不开放 Linux TUN，不发布、不提交或推送代码。
