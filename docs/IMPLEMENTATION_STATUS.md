# RainLink 实现与验收清单

更新：2026-10-20。依据完整开发方案及实时 Figma，持续更新；“已实现”不等于所有平台均已验收。

最新 Linux 服务管理进展：设置页已接入状态、安装/更新、卸载、恢复、取消和连接互斥，新增独立 `manage-tun-service` 通道。Flutter 全量 454 项通过，最后的未知状态显示修正另经 6 项 UI 回归验证；静态检查与 Linux 管理/文件检查单元测试通过。真实 `pkexec` 管理 VM 在下载依赖时失败，未执行管理闭环；活动桌面认证弹窗、取消后的真实恢复及 Linux GUI 视觉仍待验收，公开 TUN 保持关闭。范围与复现见[服务管理阶段记录](verification/linux-tun-service-management.md)。以下各阶段结果及旧摘要保持其当时范围。

最新 Linux 权限日志续验：核心 check / run 的脱敏输出、授权及恢复日志已传回普通宿主，复用原日志 UI；普通宿主增至 15 个场景。Linux 网络 414 个、日志压力 20 轮共 500 个、真实 systemd / polkit 3 个、Windows 164 个 Go 通过事件分别通过，详见[权限日志验收](verification/linux-tun-logs.md)。真实 VM 使用临时 UID / action 的 YES / NO 规则，未验证活动桌面密码弹窗。GUI 管理和分发仍待推进，公开 Linux TUN 保持关闭。本阶段没有 Dart 修改或新 Flutter 执行；此前 440 项结果保留。用户要求暂时收尾并保存代码，检查点见[阶段记录](verification/closeout-20261017.md)。

前阶段 Linux 安装续验：新增固定路径管理员安装、升级、卸载及持久事务恢复，三十次 SIGKILL 恢复和完整 CLI fixture 通过。独立 Debian 13 / systemd 257 的实际安装、socket 就绪、退出钩子、升级状态保持、覆盖项拒绝、资源租约阻止替换及卸载恢复通过，见[安装验收](verification/linux-tun-install.md)。下文前阶段段落保留其当时范围。

上一轮 Linux 续验将 TUN 接入普通 Manager 的真实 Secret Service、节点/链/规则、连接、遥测、模式与恢复确认。14 个完整宿主场景通过，包括共存接管、异常退出、停止取消与重试、授权取消及规则损坏；当前 359 个 Linux、164 个 Windows Go 通过事件，Flutter 440 项与静态检查通过，见[宿主接入验收](verification/linux-tun-manager.md)。完整网络与原安装文件保持。该轮的真实 polkit / systemd、服务安装/升级/卸载和权限日志尚未验收，公开 Linux TUN 继续关闭。前阶段[转发与原生客户端](verification/linux-tun-forwarding.md)的 120 次压力及一次未定位历史失败继续保留；[权限验收](verification/linux-tun-permission.md)与[核心验收](verification/linux-managed-tun-core.md)保留各阶段快照。

上一轮 KDE 配置后端与 GNOME / KDE 加密恢复租约已通过旧版日志和跨桌面恢复验收：当时隔离非 root WSL 中 242 个 Linux Go 通过事件、Windows 162 个回归事件及 8 项 Flutter 状态协议测试通过。KDE 结果限 Qt6 / KConfig6 / libproxy 实际后端和宿主，完整 Plasma 与 Linux GUI 仍待验收，见 [KDE 验收](verification/linux-kde-proxy.md)。

上一轮订阅兼容确认、schema 7 迁移、八个双端原生渲染场景和 Windows 双跳代理链续验通过。三个已存 HY2 节点真实 HTTPS 测速全部成功；订阅直连失败后，经 HY2 及真实生产下载器成功获取并解析 68 个节点，其中 16 个 HY2。已接入当前连接下载路径，两个 HTTP 节点仍失败，见[订阅兼容验收](verification/subscription-compatibility.md)。本轮重新通过 440 项 Flutter 全量与静态分析，没有重跑原生视觉或外网订阅，0.1.0+4 预览包保持原样。

Android 原生实现、构建复现、完整 APK 16 KB 对齐、Figma 核对和未完成范围见 [Android 验收](verification/android.md)。最近 Android 原生产物验收包含 5 项 Kotlin 单元测试与 10 项原生测试，本轮没有重新打包。移动主页面、连接、日志、通用设置深浅主题有 16 张渲染 fixture；44 个 SVG 与已保存的 Figma 导出一致。[自动连接与提醒](verification/android-startup-notifications.md)、[配置与切网](verification/android-configuration.md)及[遥测](verification/android-telemetry.md)分别记录真实核心与界面证据。

| 范围 | 当前状态 | 后续验收 |
| --- | --- | --- |
| Windows 连接、模式、系统代理、恢复 | 已接入真实核心 | 继续保留真实回执与取消/异常恢复 |
| HTTP / SOCKS5 / SS / VLESS / VMess / Trojan / Hysteria2 / TUIC v5 | Windows 八协议已实现，HY2 有真实机场验证 | VMess/TUIC 的认证、TLS、UDP、双向混合链有真实本机核心验证；远程服务商尚未逐一验证，HY2 上游仍有间歇性超时 |
| 订阅、分组、用量、到期、更新 | 已实现，支持 Clash、sing-box 兼容节点和分享链接；部分兼容内容在原弹窗逐项确认，自动更新保留旧数据 | 更多来源与远端协议组合；不直接执行订阅中的完整配置，见[订阅兼容验收](verification/subscription-compatibility.md) |
| 节点收藏、别名、隐藏与独立测速 | Windows 已实现，双端紧凑 UI 已接入 | 刷新保留、旧版本迁移、取消及活动连接隔离已有验收；远程 HY2 仍有间歇超时，Android 原生测速已接入，远端与其余平台仍待验收 |
| 实时连接 | Windows / Android 已接入并在本机核心验收 | 搜索/筛选/暂停/关闭/文件导出；真实流终止已验证，进程未知如实显示；Android 导出使用系统文件保存器 |
| 核心日志 | Windows / Android 已接入；Linux 托管 TUN 核心新增实际 systemd / polkit 日志验收 | 原页面复用采集/脱敏/持久保留/筛选/暂停/清空/导出；Linux 私有缓冲 2,000 条、公共批次 16 条，清空屏障与 IPC 背压已验收；Linux GUI 仍待验收，见[权限日志](verification/linux-tun-logs.md) |
| 自定义规则 | Windows 已实现并验收；Android 规则链与三模式已有实际核心验收 | 域名/IP/兜底、CRUD/启停/排序、节点/分组/代理链出站、真实编译、失败保留、连接快照及重连应用；移动端全部编辑流程仍需逐项验收 |
| 可视化代理链 | Windows 已实现并验收；Android 已验收移动编辑器保存及概览连接 | 2–5 跳增删换序/更换/搜索、保存选择、真实 detour；两端本机 HTTP 双跳及反向重连已验证，独立逐段测试与取消目前仅 Windows 完成实际验收，远程多协议组合尚未逐一验证 |
| 流量 | Windows 已实现持久曲线、日/周/月、保守归属排行及 CSV | 全局/直连可确认归属，规则与模式切换后明确记为未归属；进程与规则多出站的精确排行仍待补 |
| 设置六分类 | 已接入主题、紧凑/标准密度、字号、减少动效、DNS/引导解析、本地端口、日志级别、确认重启、真实版本与开源许可 | 普通网络表单先经独立核心校验，下次连接或确认重启应用；应用更新详见下行 |
| Windows 应用更新 | 已接入固定 GitHub 源、渠道、可取消下载、摘要校验、退出交接、程序/数据库回滚及持久日志/独立启动器；真实 AOT 隔离安装、失败回滚及强杀恢复通过 | 当前源尚无可用发布版本，正式线上升级未验收；物理断电、签名及启动器在线替换待验收/实现 |
| 高级配置 | Windows 已接入受控 YAML/JSON 覆盖、实际核心校验、确认应用、上一版恢复及结构化导出；Android 已验收实际在线应用与恢复 | 保留原目标/模式/跳点，失败恢复及两版配置原子保存已有两端证据；不支持任意完整配置，移动端编辑弹窗全流程仍待逐项验收 |
| Windows 托盘 / 开机启动 / 自动连接 / 连接通知 / 订阅到期提醒 | 已实现并验收隐藏后传输、窗口恢复、注册表写入回读和恢复；到期提醒默认关闭、聚合数量、持久去重及失败重试 | 真实注销/启动尚未测试；通知仅确认系统接收，未证明系统显示；关闭应用不定时唤醒 |
| Windows TUN | 已接入权限进程、真实 TCP/UDP/DNS、概览切换和退出恢复 | 已有管理员环境实机与隔离 UI 验证；标准用户 UAC 同意/拒绝、IPv6 公网及其他网络环境待验收 |
| 分发 | Windows schema 2 ZIP、独立恢复入口与本地更新事务已接入 | 正式发布、签名安装包、卸载恢复、旧布局/启动器自动迁移及其他平台分发 |
| Linux 核心宿主 | amd64 本地端口、Secret Service、GNOME / KDE6 及跨桌面恢复已有隔离验收；普通 Manager 的 TUN 15 场景与脱敏日志通过，实际 systemd / polkit 允许和拒绝授权通过 VM 验收 | 活动桌面认证弹窗、GUI 安装管理、同 selector 外部并发、KDE5、完整桌面、分发、切网/休眠/注销待验收；权限 IPC 需 Linux 6.5+，公开 TUN 仍关闭，见[权限日志验收](verification/linux-tun-logs.md) |
| macOS 核心宿主 | 尚未完成 | 平台代理、安全存储、构建及实机验收 |
| Android 网络服务 | 已接入 Keystore、系统隧道、protect/bind、前台服务、原会话恢复、重连、实时连接及日志、启动自动连接、通知与系统文件保存；隔离模拟器 IPv4/IPv6/DNS、后台、低内存及同隧道 Wi-Fi/蜂窝/断网恢复通过 | 真机授权、真实订阅、真机切网、系统文件分享、厂商通知与后台限制、正式签名分发 |
| iOS 网络服务 | 尚未接入 | libbox、Network Extension、共享凭据、签名与真机验收 |
| Figma 双端布局与原生图标 | 已有资产及部分页面对齐；前阶段实时导出 44 个 SVG、品牌完整像素、27 个原生 PNG 与 9 尺寸 ICO 核验通过，见[图标复核](verification/runtime-audit-20261017.md)；最新日志阶段只读取桌面概览和日志参考 | 全页面、弹窗、主题、960×640/393×852、字体缩放核验 |

实时 Figma 本次读取的连接/日志/规则截图位于 `docs/verification/reference/`；代理链对照、运行截图及验收见 `verification/chains.md`。视觉测试样例与真实公网测试证据分别标注。其余完整需求仍以 `DEVELOPMENT_PLAN.md` 和 `plan/UI_INVENTORY.md` 为准。

订阅添加与详情的本轮 Figma 对照见 `verification/subscription-compatibility.md`：十个 SVG 实时重导出一致，40 张深浅主题截图覆盖四种尺寸；移动尺寸由 Windows 原生 runner 渲染，本轮没有重新进行 Android/iOS 设备验收。主题脚本已显式注入初始主题并断言亮度，避免仅修改截图文件名而实际仍使用深色主题。

VMess / TUIC 与添加弹窗的兼容范围、隔离集成、真实 UDP 和双协议链验证见 `verification/protocols.md`；全产品和移动服务仍按上表继续开发。

节点本地覆盖、独立测速及 Figma 节点页面对照见 `verification/node-management.md`。移动节点行保持 56 高、44 点击区，普通字号时单个页面主操作与标题并排，窄屏和大字模式自动换行。

密度与相关双端布局验收见 `verification/density.md`。默认紧凑，标准模式节点行改为 64；手机连接和日志使用分层列表。287 项 Flutter 测试、Windows 真实保存/失败恢复/会话保留及 140 张 fixture 布局截图通过，该阶段移动原生服务尚未接入；Android 新进展见下文。

设置使用桌面六分类侧栏及移动独立详情页，返回统一在左上角。真实 Windows DNS、连接保留、设置重启与持久化验收见 `verification/settings.md`；本轮加入高级配置后共有 80 张双端深浅主题截图，见 `verification/advanced-config.md`。该阶段移动截图只证明布局；Android 后续原生验收见下文。

高级配置的字段范围、优先级、真实 DNS/分流与恢复、取消竞态及两版配置原子持久化见 `verification/advanced-config.md`。默认不覆盖界面设置，基础表单保存不会覆盖高级片段。

订阅到期提醒在通用设置内独立开启，提前 3 天及到期时提醒；正常重开去重、真实 Windows 回执、SQLite 写入失败重试、通知回调恢复窗口并跳转分组见 `verification/subscription-expiry.md`。该阶段 303 项 Flutter 测试及 32 张新增 fixture 布局截图通过；Release 入口为 `verification/desktop-build.json`。最新 Android 原生提醒已接入并复用同一去重逻辑，见 `verification/android-startup-notifications.md`；未运行时后台唤醒仍未接入。

应用更新与中断恢复续验见 `verification/app-updates.md`、`verification/app-update-recovery.md`：该阶段 332 项 Flutter、静态分析、79 个 Go 通过测试事件、26 个跳过及 5 项 Python 打包回归通过。真实 Windows 下载/取消、AOT 安装、失败回滚、强杀 helper 后启动器自动恢复通过。更新页 5 个 SVG 从 Figma 重新导出一致，原生 27 个 PNG、9 尺寸 ICO 及启动器资源已核对；前轮 56 张双端 fixture 保留。该阶段恢复预览包为 0.1.0+3；旧布局首次需完整手动升级，后续在线包要求复用启动器。用户节点、订阅、偏好、开机启动和系统代理摘要保持一致。最新包已更新为 `build/RainLink-windows-x64-subscriptions-preview.zip`，0.1.0+4；本轮没有重跑完整 AOT 更新事务。物理断电、正式签名分发、其他平台服务与全页面校准继续进行。
