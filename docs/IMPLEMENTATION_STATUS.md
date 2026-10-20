# RainLink 实现与验收清单

更新：2026-10-21。依据完整开发方案及实时 Figma，持续更新；“已实现”不等于所有平台均已验收。

按用户要求暂停开发并保存、推送，见[最新暂停检查点](verification/linux-tun-product-modes.md)。修正 Linux 产品 TUN 测试源站拓扑及双栈默认路由后，三模式、规则重连、连接中开关、正常断开和活动退出共 64 个回执与源站匹配，七次内核恢复通过；44 个当前 Figma SVG、26 个颜色映射一致。本轮只修改 QA fixture，Bash/Python 检查通过，未重跑 Dart/Go 全量测试。服务失效修复、AT-SPI/GTK 警告及完整视觉待续验，默认包未替换；下列关闭状态属于历史阶段。

Android 流量续验：专用 AVD 的真实系统隧道中，同一会话三模式各完成 12 次独立 UID 请求，36 个完整正文回执、24 次代理与 12 次直连均回读。已结束连接、真实包名、SQLite 重开、重复采样去重、两个排行分区及页面 CSV 通过；五张实际 Android 渲染截图和当前 Figma 七个使用 SVG 已核对。详见[Android 流量与应用归属](verification/android-traffic-accounting.md)。此阶段新增验收代码，不改变生产统计口径；正式第三方应用/真机、Apple 原生和完整五平台继续推进，公开 Linux TUN 仍关闭。

Android 更新续验：接入固定发布源、渠道、可取消 APK 下载/摘要、身份与签名复验、网络恢复后系统安装，以及跨进程安装回执。独立 AVD 实际拒绝授权、取消安装、4 → 5 替换、普通新版本重开和节点/浅色偏好保留已验收；同时修复移动系统栏主题对比度和 iOS 安全区下概览的紧凑间距。最终共享回归、44 张更新页布局、四个使用图标和 APK 检查见[Android 应用更新](verification/android-app-update.md)。正式线上升级、真机及 Apple 原生仍待验收，公开 Linux TUN 保持关闭；历史记录保留各阶段范围。

扫码导入续验：移动添加弹窗已接真实相机，桌面补单节点分享链接粘贴；识别只预填，确认才保存/下载，保留订阅自动成组与手动节点未分组。522 项 Flutter、静态分析和 32 张布局通过；Android 普通 APK 在独立 AVD 经真实 CameraX/ML Kit 帧完成拒绝、暂停/恢复、HTTP 保存、订阅一次确认下载及流量/到期/重启回读。三个使用图标与当前 Figma 原生 SVG 一致，独立 Debug APK 完成签名/核心/16 KB 检查。无 Mac，Apple 原生和 Android 真机仍待验收，公开 Linux TUN 继续关闭；见[扫码导入](verification/qr-import.md)，下方历史记录保持各阶段范围。

流量归属续验：核心在真实 TCP/UDP 回调累计实际出站及进程 basename/package，保留已结束连接；两种排行各自等于总计，未知和容量溢出不推测。schema 8 将日/时段、两个分区和来源检查点同事务保存，旧聚合迁移、重复样本、时钟回拨及非法来源回滚已覆盖。原流量卡片内新增“出站/应用”，960×640 紧凑窗口图表和排行并排，移动和大窗口保留纵向结构。最新平台证据、构建和 Figma 核对见[流量归属验收](verification/traffic-accounting.md)；下列历史记录不覆盖。

macOS 基础接入：补齐共享本地会话、Security.framework 主密钥 helper 和开发构建/本地签名流程，签名后核心在编译时锁定摘要。两架构宿主及测试程序交叉编译/vet 通过；474 项 Flutter、126 个 Windows Go 通过事件与 2 项真实核心回归、59 个 Linux 凭据通过事件、8 项 Mac 构建流程 fixture 通过，44 个 SVG 从当前 Figma 重导出一致。没有 Mac，Swift/Xcode/Keychain/原生运行尚未验证，系统代理、TUN、菜单栏及 iOS 仍未完成，公开 Linux TUN 继续关闭。见[macOS 基础接入](verification/macos-foundation.md)，下列历史阶段保持其原始范围。

生命周期续验：Flutter 3.29.3 / Dart 3.7.2 加 Linux 文件选择通道提前释放，已消除复现过的光标失效、弱引用及无引擎通道警告。473 项 Flutter、284 文件格式、静态分析、真实 GTK 导出/托盘/通知、两套渲染器共 108 张布局通过；最终 Linux 包在致命 GTK 警告模式下三次退出、四次隐藏恢复通过，仍保留一条上游隐式视图诊断。Windows Release 与 Android Debug/测试 APK 重新构建，5 项 Kotlin 单元通过，Lint 无错误、有 4 条警告；Android 签名、核心与 16 KB 对齐通过。746 项源码输入一致，当前 Figma 设置已重新读取，44 个同源 SVG 保持一致。详见[生命周期与 SDK 升级](verification/linux-flutter-lifecycle.md)。完整桌面/发行版、真机与 macOS/iOS 等仍未完成，公开 Linux TUN 继续关闭；下方阶段范围保持原样。

通用设置续验：Linux 自动启动、托盘与独立通知已通过真实 Xfce 面板/Dunst 流程，面板消失恢复窗口、重启重新注册和通知跳转分组均已确认；修复特殊安装路径、较早托盘注册和启动偏好校验问题。473 项 Flutter、8 项原生检查、静态分析与当前 Figma 44 个 SVG 通过；745 项产品输入一致，默认 Linux Release 包已更新并经实际保存/退出/重开。见[通用系统功能](verification/linux-desktop-system-services.md)。GTK/Flutter 退出诊断仍存在，完整桌面/发行版、真实注销启动和其他平台继续验收，公开 Linux TUN 保持关闭。

活动图形授权续验：修复普通 broker 继承 Linux capability 时 pkexec 的 `/proc/<pid>/exe` 读取失败，新增真实继承能力/全部 Go 线程回归。最终完整 Linux tar 在新用户 X11/logind/lxpolkit 会话中通过密码授权安装、卸载和退出，无管理进程或事务残留；733 项产品输入、181 项原生/构建输入及当前 Figma 44 个 SVG 一致。最新包摘要见[图形授权与最终包](verification/linux-graphical-service-management.md)。GTK/Flutter 退出诊断、完整桌面/发行版兼容与正式分发仍待处理，公开 Linux TUN 继续关闭。本阶段未重跑旧的 Flutter/108 张布局结果，下方保留历史范围。

普通用户写入取消续验：新增内核 fanotify 控制的真实替换场景，普通 UID 经生产 broker / pkexec 在宿主已替换、核心临时文件完整写入后发出 cancel 或 EOF。启用/停用状态共四项通过，原宿主、清单和服务状态恢复，事务及 root worker 清理通过；详见[普通用户写入取消](verification/linux-broker-write-cancellation.md)。图形认证仍继续验收，公开 Linux TUN 保持关闭；下列旧阶段范围保持原样。

概览续验：增加真实近期连接摘要与列表入口，小窗口连接卡和图表/健康区更紧凑，并保留两行节点状态。468 项 Flutter 回归、静态分析与 Windows/Linux 真实核心请求/关闭通过；两套桌面渲染器各 54 张布局截图通过。729 项源码输入与 QA 副本一致，Linux Release 预览包已重新构建；详见[概览与紧凑布局](verification/overview-recent-connections.md)。以下快照保留原始测试与产物摘要。

Linux 桌面预览续验：普通 Linux 用户已完整构建并打包 x64 tar，修复只读 Go 源目录、Ninja 工具链、SQLite 下载与安装路径重试、X11 窗口图标问题。解压 Release 的带认证节点添加、重开选择、真实 HTTP 回执、GNOME 系统代理接管与关闭恢复通过；原生窗口和八个主页面、1 项冒烟、38 张布局及 40 张权限服务 fixture 通过，静态分析与资源检查通过。44 个 SVG 已从当前 Figma 原生更新，28 个 PNG 与 ICO 复核通过。活动桌面认证、完整桌面/发行版兼容性和正式分发仍待完成，公开 TUN 保持关闭，见[桌面预览验收](verification/linux-desktop-preview.md)。

安装取消续验：修复版本清单写入后、正式提交前可能漏掉取消的问题，50 个取消边界、原有 30 次 SIGKILL 恢复及整套安装/管理单元通过。真实 systemd 下的安装/升级/卸载写入后取消、提交后版本保持共五项通过，取消由私有测试 checkpoint 注入；同一宿主另通过八种普通用户授权与管理场景。普通 broker 恰好在写入中发出取消仍待端到端验证，图形桌面与分发继续进行；公开 Linux TUN 保持关闭，见[安装取消与恢复](verification/linux-install-cancellation.md)。本轮没有新的 Flutter 或视觉执行。

等待认证取消续验：修复仅关闭输入管道不能撤销挂起 pkexec 的问题；普通用户先撤销管道，再终止尚未切换 root 的授权进程。真实 polkit 的 AUTH_ADMIN 取消、EOF、代理拒绝三项，以及五种服务管理回归通过。证据使用 D-Bus process-subject 测试代理，不代表图形认证窗口或密码验收；写入期间取消、Linux GUI 和分发继续推进，见[等待认证取消](verification/linux-service-authentication-cancellation.md)。公开 Linux TUN 仍关闭，未重新运行 Flutter 或全页面视觉。

最新服务管理续验：普通 UID 65534 经实际 pkexec/polkit 完成拒绝、安装/恢复/重复安装/卸载、不同构建替换并保留禁用状态、授权后锁等待时取消及 EOF，均通过隔离 VM。Linux/macOS 安全退出复用现有流程，并等待管理操作与回读；460 项 Flutter、静态检查和 40 张深浅主题 fixture 通过，44 个 SVG 与已保存的 Figma 导出一致。活动桌面认证弹窗、事务写入期间取消、Linux GUI 实机、正式分发与最新全页面 Figma 核对仍未完成，公开 Linux TUN 保持关闭，详见[服务管理与安全退出续验](verification/linux-tun-service-management-acceptance.md)。下文首次服务管理结果属于 `ff17b10` 检查点。

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
| 扫码导入、分享链接预填 | 移动新增扫码；八协议共享解析并回读保存；Android 独立 AVD 真实相机、确认下载、自动组名及用量/到期通过；桌面新增单节点粘贴 | Android 真机与 iOS 原生仍待验收；扫码只预填，见[扫码验收](verification/qr-import.md) |
| 节点收藏、别名、隐藏与独立测速 | Windows 已实现，双端紧凑 UI 已接入 | 刷新保留、旧版本迁移、取消及活动连接隔离已有验收；远程 HY2 仍有间歇超时，Android 原生测速已接入，远端与其余平台仍待验收 |
| 实时连接 | Windows / Android 已接入并在本机核心验收；Windows/Linux 概览新增真实近期连接摘要并通过列表关闭请求 | 搜索/筛选/暂停/关闭/文件导出；近期摘要仅为当前页面观测，不是完整历史；Android 导出使用系统文件保存器 |
| 核心日志 | Windows / Android 已接入；Linux 托管 TUN 核心新增实际 systemd / polkit 日志验收 | 原页面复用采集/脱敏/持久保留/筛选/暂停/清空/导出；Linux 私有缓冲 2,000 条、公共批次 16 条，清空屏障与 IPC 背压已验收；Linux GUI 仍待验收，见[权限日志](verification/linux-tun-logs.md) |
| 自定义规则 | Windows 已实现并验收；Android 规则链与三模式已有实际核心验收 | 域名/IP/兜底、CRUD/启停/排序、节点/分组/代理链出站、真实编译、失败保留、连接快照及重连应用；移动端全部编辑流程仍需逐项验收 |
| 可视化代理链 | Windows 已实现并验收；Android 已验收移动编辑器保存及概览连接 | 2–5 跳增删换序/更换/搜索、保存选择、真实 detour；两端本机 HTTP 双跳及反向重连已验证，独立逐段测试与取消目前仅 Windows 完成实际验收，远程多协议组合尚未逐一验证 |
| 流量 | 已实现日/周/月、持久曲线、CSV 和独立的实际出站/应用排行，含已结束连接；桌面及 Android transport 接入，schema 8 原子记账 | Windows/Linux 范围见[流量归属](verification/traffic-accounting.md)；Android 专用 AVD 真实三模式 36 次请求、shell 包名、UI/SQLite/CSV 与重开已续验，见[Android 续验](verification/android-traffic-accounting.md)。真机/第三方应用、macOS 原生、未知/超限和突然中断边界保留 |
| 设置六分类 | 已接入主题、紧凑/标准密度、字号、减少动效、DNS/引导解析、本地端口、日志级别、确认重启、真实版本与开源许可 | 普通网络表单先经独立核心校验，下次连接或确认重启应用；应用更新详见下行 |
| Windows 应用更新 | 已接入固定 GitHub 源、渠道、可取消下载、摘要校验、退出交接、程序/数据库回滚及持久日志/独立启动器；真实 AOT 隔离安装、失败回滚及强杀恢复通过 | 当前源尚无可用发布版本，正式线上升级未验收；物理断电、签名及启动器在线替换待验收/实现 |
| Android 应用更新 | 已接入固定 GitHub 源、APK 下载/校验、网络恢复、系统授权及安装回执；独立 AVD 真实拒绝/取消、普通应用 4 → 5 升级、节点及主题保留通过 | 正式源线上升级、正式签名、真机及厂商安装器；见[验收](verification/android-app-update.md)，iOS/macOS/Linux 应用更新未计为已完成 |
| 高级配置 | Windows 已接入受控 YAML/JSON 覆盖、实际核心校验、确认应用、上一版恢复及结构化导出；Android 已验收实际在线应用与恢复 | 保留原目标/模式/跳点，失败恢复及两版配置原子保存已有两端证据；不支持任意完整配置，移动端编辑弹窗全流程仍待逐项验收 |
| Windows 托盘 / 开机启动 / 自动连接 / 连接通知 / 订阅到期提醒 | 已实现并验收隐藏后传输、窗口恢复、注册表写入回读和恢复；到期提醒默认关闭、聚合数量、持久去重及失败重试 | 真实注销/启动尚未测试；通知仅确认系统接收，未证明系统显示；关闭应用不定时唤醒 |
| Linux 自动启动 / 托盘 / 系统通知 | 已接入 XDG 启动项、StatusNotifier 与独立通知，真实面板和 Dunst 的显示/动作、丢失恢复及重启注册通过；Release 保存与重开通过 | 真实注销启动、完整 GNOME/Plasma/Wayland、其他发行版和 GTK/Flutter 生命周期仍待验收；见[通用系统功能](verification/linux-desktop-system-services.md) |
| Windows TUN | 已接入权限进程、真实 TCP/UDP/DNS、概览切换和退出恢复 | 已有管理员环境实机与隔离 UI 验证；标准用户 UAC 同意/拒绝、IPv6 公网及其他网络环境待验收 |
| 分发 | Windows schema 2 ZIP、独立恢复入口与本地更新事务已接入；Linux x64 Release tar 已构建、校验并解压启动 | 正式发布、签名安装包、卸载恢复、Windows 旧布局/启动器迁移、Linux 其他发行版兼容及其他平台分发 |
| Linux 核心宿主 | amd64 本地端口、Secret Service、GNOME / KDE6、跨桌面恢复、X11 GUI、认证节点及真实 HTTP 已有隔离验收；生产 broker 写入取消和活动 logind/lxpolkit 的密码授权已完成；最新通用系统功能与完整 tar 保存/重开通过 | GTK/Flutter 退出诊断、同 selector 外部并发、KDE5、完整 GNOME/Plasma/Wayland、正式分发、切网/休眠/注销仍待验收；公开 TUN 继续关闭，宿主授权范围见[图形授权与最终包](verification/linux-graphical-service-management.md)，最新包见[通用系统功能](verification/linux-desktop-system-services.md) |
| macOS 核心宿主 | 已补共享本地会话、Keychain helper 与开发构建代码；Intel / Apple Silicon 交叉编译通过，尚无原生运行证据 | Mac Swift/Xcode/CocoaPods 与 Keychain 授权、真实核心、系统代理恢复、菜单栏/启动项、正式签名与分发，见[基础接入](verification/macos-foundation.md) |
| Android 网络服务 | 已接入 Keystore、系统隧道、protect/bind、前台服务、原会话恢复、重连、实时连接及日志、启动自动连接、通知与系统文件保存；隔离模拟器 IPv4/IPv6/DNS、后台、低内存及同隧道 Wi-Fi/蜂窝/断网恢复通过 | 真机授权、真实订阅、真机切网、系统文件分享、厂商通知与后台限制、正式签名分发 |
| iOS 网络服务 | 尚未接入 | libbox、Network Extension、共享凭据、签名与真机验收 |
| Figma 双端布局与原生图标 | 当前 Figma 44 个 SVG 与运行资源一致，28 个原生 PNG、9 尺寸 ICO 通过；八个桌面主页面和移动尺寸的新一轮 Windows/Linux 布局共 108 张，见[概览续验](verification/overview-recent-connections.md)；前轮窗口图标和服务状态范围保留 | 数据与测量指标差异明确保留；全页面弹窗、真实移动设备及各平台原生主题/缩放仍需核验 |

实时 Figma 本次读取的连接/日志/规则截图位于 `docs/verification/reference/`；代理链对照、运行截图及验收见 `verification/chains.md`。视觉测试样例与真实公网测试证据分别标注。其余完整需求仍以 `DEVELOPMENT_PLAN.md` 和 `plan/UI_INVENTORY.md` 为准。

订阅添加与详情的本轮 Figma 对照见 `verification/subscription-compatibility.md`：十个 SVG 实时重导出一致，40 张深浅主题截图覆盖四种尺寸；移动尺寸由 Windows 原生 runner 渲染，本轮没有重新进行 Android/iOS 设备验收。主题脚本已显式注入初始主题并断言亮度，避免仅修改截图文件名而实际仍使用深色主题。

VMess / TUIC 与添加弹窗的兼容范围、隔离集成、真实 UDP 和双协议链验证见 `verification/protocols.md`；全产品和移动服务仍按上表继续开发。

节点本地覆盖、独立测速及 Figma 节点页面对照见 `verification/node-management.md`。移动节点行保持 56 高、44 点击区，普通字号时单个页面主操作与标题并排，窄屏和大字模式自动换行。

密度与相关双端布局验收见 `verification/density.md`。默认紧凑，标准模式节点行改为 64；手机连接和日志使用分层列表。287 项 Flutter 测试、Windows 真实保存/失败恢复/会话保留及 140 张 fixture 布局截图通过，该阶段移动原生服务尚未接入；Android 新进展见下文。

设置使用桌面六分类侧栏及移动独立详情页，返回统一在左上角。真实 Windows DNS、连接保留、设置重启与持久化验收见 `verification/settings.md`；本轮加入高级配置后共有 80 张双端深浅主题截图，见 `verification/advanced-config.md`。该阶段移动截图只证明布局；Android 后续原生验收见下文。

高级配置的字段范围、优先级、真实 DNS/分流与恢复、取消竞态及两版配置原子持久化见 `verification/advanced-config.md`。默认不覆盖界面设置，基础表单保存不会覆盖高级片段。

订阅到期提醒在通用设置内独立开启，提前 3 天及到期时提醒；正常重开去重、真实 Windows 回执、SQLite 写入失败重试、通知回调恢复窗口并跳转分组见 `verification/subscription-expiry.md`。该阶段 303 项 Flutter 测试及 32 张新增 fixture 布局截图通过；Release 入口为 `verification/desktop-build.json`。最新 Android 原生提醒已接入并复用同一去重逻辑，见 `verification/android-startup-notifications.md`；未运行时后台唤醒仍未接入。

应用更新与中断恢复续验见 `verification/app-updates.md`、`verification/app-update-recovery.md`：该阶段 332 项 Flutter、静态分析、79 个 Go 通过测试事件、26 个跳过及 5 项 Python 打包回归通过。真实 Windows 下载/取消、AOT 安装、失败回滚、强杀 helper 后启动器自动恢复通过。更新页 5 个 SVG 从 Figma 重新导出一致，原生 27 个 PNG、9 尺寸 ICO 及启动器资源已核对；前轮 56 张双端 fixture 保留。该阶段恢复预览包为 0.1.0+3；旧布局首次需完整手动升级，后续在线包要求复用启动器。用户节点、订阅、偏好、开机启动和系统代理摘要保持一致。最新包已更新为 `build/RainLink-windows-x64-subscriptions-preview.zip`，0.1.0+4；本轮没有重跑完整 AOT 更新事务。物理断电、正式签名分发、其他平台服务与全页面校准继续进行。
