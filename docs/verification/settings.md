# 设置、DNS 与核心重启验收

2026-10-17。设置六分类使用真实偏好与核心接口，已验收范围为 Windows；移动只完成独立 UI 与共享业务布局。

## 实现与使用

桌面设置左侧保留通用、外观、网络、核心引擎、更新和关于；更窄空间自动改为可换行分类。移动首页使用紧凑分类列表，进入详情后左上箭头或系统返回回到分类。

外观支持跟随系统、深色、浅色，字号为标准/1.15/1.3，叠加系统 TextScaler；减少动效实际影响页面、主题和开关。偏好分别保存到现有 Preferences 表的 appearance.preferences、network.runtime，主题继续使用 appearance.theme，不新增数据库迁移。

网络提供系统 DNS、HTTPS 加密 DNS、自定义 HTTPS/UDP、本地混合端口和 IPv6 解析。引导 DNS 是用于解析 HTTPS DNS 域名的 IP，不是备用解析器。DNS URL 拒绝认证、查询、片段与非法端口；混合端口 0 自动或 1–65535 固定，只监听回环。IPv6 开关控制解析策略，不冒充禁用所有 IPv6 字面地址连接。

点击保存先通过独立宿主实际 sing-box check，再串行写入确认状态；失败保留原值。保存不重建活动连接，下次连接生效。核心页确认重启后保留原活动目标、规则及链快照和当前模式，应用最新网络与日志设置。连接回执逐项核对实际 runtimeSettings，防止旧宿主忽略配置却返回成功。

解析测试实际查询 example.com 的 A 记录，显示 IP 和毫秒；可取消。system、UDP 和 HTTPS 各有真实请求实现，独立诊断宿主不更改系统 DNS、系统代理或正常会话。应用和核心版本取自实际构建/宿主，关于页注册 Inter、Noto Sans SC、Roboto Mono 及 sing-box 许可，发布包继续附核心源码。

Windows 通用支持当前用户开机启动、启动时自动连接、关闭窗口时退出或保留到托盘、托盘图标和连接状态通知。默认不自动连接、不启用开机启动，关闭窗口默认退出。通用与连接偏好分别保存到 general.preferences、connection.preferences，不保存活动会话。自动连接等待节点、选择及核心就绪，使用已保存的当前选择、代理模式和系统代理选项；取消期间的迟到加载不会重新触发连接。

托盘包含显示窗口、开始/取消/断开连接和退出。关闭到托盘保留活动会话，真正退出先确认网络恢复，等待排队的偏好写入，再关闭宿主和原生资源；恢复失败保留可操作窗口。关闭托盘图标时先恢复窗口，同时取消托盘关闭行为和托盘通知，避免应用隐藏后无法恢复。开机启动写入当前用户 Run/RainLink，使用当前可执行文件并回读确认；关闭时只删除属于当前安装路径的项。

连接通知只包含固定状态，不含节点或认证信息。原生接口确认通知已提交，不保证 Windows 在勿扰等状态下实际显示。后续已独立接入默认关闭的订阅到期提醒，行为、真实系统回执及持久去重见 [到期提醒验收](subscription-expiry.md)。移动及尚未接入原生接口的平台不提供假开关；Windows 应用更新后续已接入版本源、渠道、下载、安装交接和失败回滚，真实 AOT 与布局证据见 [应用更新验收](app-updates.md)。紧凑/标准密度及 YAML/JSON 已接入，见 [密度验收](density.md)与[高级配置](advanced-config.md)。

## 真实 Windows 集成

`app/integration_test/windows_settings_test.dart` 在真实 Flutter / Go / sing-box 中使用临时 SQLite、UDP DNS 与本机 HTTP 源站：

- 活动会话中校验、测试 DNS 和保存设置，原 sessionId 保留。
- 取消重启保持连接，确认后实际应用指定混合端口；选择 B 后重启仍使用原活动 A。
- 新会话通过自定义 DNS 解析域名到本机源站，DNS 收到 6 次查询，源站实际完成 1 次传输。
- 取消不响应的 DNS 测试不打断连接，关闭重开数据库后设置一致。

该测试没有启用系统代理，不写用户数据库。实际回执为 `settings/windows-evidence.json`，测试日志为 `build/settings-windows-integration.log`。

新增 `app/integration_test/windows_desktop_integration_test.dart` 使用独立临时数据库、真实核心与本机 HTTP 源站验证自动连接及通用集成：

- 按保存的目标和直连模式启动，无系统代理修改；关闭窗口隐藏后 sessionId 不变，本机代理实际完成 1 次源站传输。
- Windows Shell 确认托盘图标已注册；隐藏窗口后发送原生激活回调，窗口恢复且 Dart 收到对应事件。
- 隐藏时关闭托盘先恢复窗口；无托盘时拒绝隐藏。
- 当前用户开机启动注册表启用、回读及恢复均通过，没有覆盖其他安装路径的项。尚未以真实 Windows 注销/重启验证启动。
- 连接通知提交成功；系统实际显示未验证。

回执为 `settings/desktop-native-evidence.json`，日志为 `build/desktop-native-integration.log`。设置隔离集成在新窗口代码下再次通过，日志为 `build/desktop-settings-native-regression.log`。恢复失败保留窗口、退出等待写入及启动取消等失败路径由强断言的组件回归覆盖。

## UI、图标与回归

实时 Figma 对照桌面设置 `2:19743`、移动设置 `2:23130`、外观 `59:46980`、网络 `59:47089` 和核心 `59:47198`，参考截图在 `reference/settings*-current.png`。9 个设置图标经原生 SVG 导出并与运行资产逐字节比较，全部相同；来源和哈希见 `settings/icon-verification.json`。

视觉集成生成 60 张 fixture 截图，覆盖 1440×900、960×640、393×852、320×640、六分类、移动首页、深浅主题及网络监听区；320 使用 1.3 倍字号。已修复桌面分类排列、主题卡片过高、Material 下拉箭头、移动关闭窗口条目和核心空版本/0 端口。桌面切换设置分类重置滚动位置；移动移除额外品牌标题栏，导航入口并入页面标题区，详情保留左上角返回。系统许可证页的返回/关闭按钮也使用 Figma SVG。截图为 `settings/settings-*-fixture.png`，只证明布局，不作为移动原生网络证据。

回归覆盖设置持久化/坏值、核心校验失败保留、DNS 取消/重试、真实解析和配置编译、重启快照/取消、托盘/注册表回读、退出失败重试及设置写入等待、320 宽与大字、TextScaler 和减少动效。Flutter 全量 244 项通过，205 个 Dart 文件格式检查和静态分析通过，最后出口排版与大字速度单位修改后重点 11 项回归再次通过。Go 全量 85 项通过、3 项需要显式启用系统代理的用例跳过；gofmt 和 go vet 通过，托盘续验未改 Go。

## Release 实窗与预览包

已构建并实际启动新版 Windows Release（0.1.0+1），逐一查看六类设置、真实核心 1.12.25-rainlink.1、托盘菜单和许可证页的 Figma 返回箭头。实窗位于 `settings/release-desktop-*.png`，该次查看保持未连接，没有修改用户设置。默认关闭行为正常退出，宿主及核心没有残留进程。

启动前后 SQLite 完整性均为 ok，schema 6，原有 68 个节点、1 个分组、0 个覆盖、4 项偏好的数量及内容摘要完全一致；当前用户开机启动项和系统代理摘要也一致。只保留摘要和数量，不记录订阅地址、节点认证或系统代理原值，回执为 `settings/release-evidence.json`。

预览包为 `build/RainLink-windows-x64-desktop-preview.zip`，41,563,185 字节，SHA-256 为 `1d982e02e04dcc5b1b113f76eb4462f98a34f777bcd15775203c57000929165e`。已核对 Release 引擎摘要、压缩包完整性、应用/AOT/宿主/核心及许可源码，包内没有用户数据库。全部摘要见 `desktop-build.json`。解压到新文件夹后运行 RainLink，沿用系统应用数据目录。

本页 Release 数据保留该阶段历史结果；最新预览包以 `desktop-build.json` 为准，后续 TUN、高级配置与密度分别见 [TUN 验收](tun.md)、[高级配置验收](advanced-config.md)与[密度验收](density.md)。全产品和其余平台尚未完成，状态以 `../IMPLEMENTATION_STATUS.md` 为准；在线更新及其他平台系统集成仍在后续范围。
