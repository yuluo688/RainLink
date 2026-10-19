# RainLink

桌面优先的五平台客户端。Flutter 负责界面与业务，Go Host 负责桌面核心边界，Android 使用 Kotlin 前台网络服务与嵌入式 libbox。

2026-10-20 开发进展：Linux「设置 → 核心引擎」已加入 TUN 权限服务管理；共享桌面退出会等待管理操作、状态回读与网络恢复。已修复等待认证和安装提交前可能漏掉取消的问题。实际 pkexec/polkit 的八种授权/管理场景，以及安装器在真实 systemd 下的五种写入后取消场景通过，后者由私有测试 checkpoint 注入取消；普通 broker 写入中取消、活动图形认证、Linux GUI 与正式分发继续验收，公开 Linux TUN 仍关闭。最新证据见[安装取消与恢复](docs/verification/linux-install-cancellation.md)，前轮 Flutter、截图与图标范围见[服务管理与安全退出](docs/verification/linux-tun-service-management-acceptance.md)。下文早期阶段测试数量保留原验收范围。

当前 Windows 版已支持 HTTP / HTTPS 代理、SOCKS5、Shadowsocks、VLESS、VMess、Trojan、Hysteria2 和 TUIC v5 的真实连接，以及订阅 URL 导入、自动分组、手动 / 自动更新、用量和到期信息。节点认证、UUID、混淆密码和订阅地址由 Windows DPAPI 加密保存；配置通过私有管道交给核心。两端按运行平台选择独立布局，共享路由与业务状态；手机横屏和桌面缩窄时保留本端导航。

操作：在「节点」点击「添加」弹窗，选择「单个节点」填写协议参数，或选择「订阅」粘贴地址。订阅自动成为一个分组，无需输入分组名称；单个节点默认未分组，只有未分组节点可移入已有 / 新建分组。在分组行点击可恢复该组上次选择的节点；详情和更新在右侧「⋯」。分组只显示名称、数量和订阅信息。选择分组或节点后，回「概览」设置代理模式、系统代理、TUN 并点击「开始连接」；改选和订阅刷新在重连后应用，当前连接保留。断开或关闭应用会恢复连接前的系统代理并清理本次 TUN。

订阅支持 Clash YAML/JSON `proxies`、sing-box JSON `outbounds` 的兼容节点，以及明文 / Base64 分享链接列表，以 Meta 兼容标识协商格式。自动读取名称、上传 / 下载 / 总量、到期时间和更新周期；没有套餐数据时显示「服务商未提供流量信息」，部分数据按实际字段展示，不推算缺失值。默认在应用运行时每 24 小时更新，服务商可通过响应头指定 1–168 小时；导入时可关闭自动更新，之后可在订阅详情修改。

遇到不支持的节点参数或远端规则、DNS 等配置，原添加 / 详情弹窗会列出原因，确认后只保存兼容节点。预览有效期 10 分钟，确认提交同一份内容，不会重新下载；取消不保存，更新未确认或失败时保留旧节点。服务商提示项单独标注；没有可用节点时拒绝整次导入 / 更新，不会删除手动移入的节点。sing-box 格式仅导入节点，不直接执行完整配置。范围与验证见[订阅兼容与确认](docs/verification/subscription-compatibility.md)。

订阅在未连接时直连下载，已连接时使用当前 RainLink 本地代理，并遵循当前代理模式与规则。连接切换期间不发起新下载；一次下载和重定向使用同一个本地端点，代理失败不会静默回退直连。直连无法获取的来源可先在概览连接可用节点，再返回更新；本轮实际经 HY2 获取并解析了 68 个节点，其中 16 个 HY2，用量和到期信息均存在。

这仍是开发预览。Hysteria 1、TUIC v4 和 iOS 网络接管尚未实现。VMess 支持 AEAD、Alter ID、TCP / WebSocket / gRPC、TLS 和 UDP 包编码；TUIC v5 支持 QUIC、三种拥塞控制、UDP 中继及证书指纹，具体兼容范围和真实测试见[八协议验收](docs/verification/protocols.md)。代理链与可编辑规则已在 Windows 接入真实核心，见[代理链验收](docs/verification/chains.md)和[规则验收](docs/verification/routing.md)。Hysteria2 支持 Clash `hysteria2` / `hy2`、分享链接、QUIC、Salamander 混淆、带宽、端口跳跃和证书 SHA-256 指纹；指纹有值时始终验证，不能被「跳过证书验证」绕过。规则默认将局域网直连、其余请求走所选目标；可在规则页添加域名/IP 规则，指定节点、分组或代理链。普通解析沿用系统。Windows Hysteria2 / TUIC 连接会选择活动的非隧道上游网卡，并对节点域名的标准 IPv4 Fake-IP 答案使用独立加密解析；其他协议和全局 DNS 不受此策略影响。出口探测失败保留错误提示，不用样例 IP 或假流量。验收记录见 [Hysteria2 真实网络续验](docs/verification/hysteria2-network.md)、[真实服务商验证及已知波动](docs/verification/windows-real-providers.md)、[订阅和多协议验证](docs/verification/windows-subscriptions.md) 与 [首次连接验证](docs/verification/windows-connection.md)。

Windows / Linux 的窗口按钮集成在顶部状态栏，支持最小化、最大化／还原、关闭、标题拖动与双击；Windows 额外支持标题区右键系统菜单。控件随深浅主题切换，macOS 保留原生窗口栏。Windows 实机截图与核验记录见 [窗口栏验证](docs/verification/window-chrome.md)。

2026-10-17 Windows 最新本地预览包：`build/RainLink-windows-x64-subscriptions-preview.zip`，版本 **0.1.0+4**。本次补齐订阅兼容确认和 sing-box 节点导入，继续包含设置六分类、Windows 托盘/启动集成、TUN、受控高级配置、紧凑/标准密度、到期提醒与更新中断恢复；默认仍为桌面小窗口紧凑布局。关闭 RainLink，将完整新包解压到新目录，运行 `rainlink.exe`；`rainlink-ui.exe` 为内部界面入口。旧布局预览需要先完整手动升级一次。打包摘要为 [desktop-build.json](docs/verification/desktop-build.json)。本轮共享数据库升级到 schema 7；程序/数据回滚的历史验收及未完成边界见[中断恢复验收](docs/verification/app-update-recovery.md)，本轮没有重跑完整 AOT 更新事务。

Linux TUN 已接入普通宿主的真实密钥环、连接、遥测、模式和确认断开；权限核心日志现通过显式协商传回原日志页面，15 个完整宿主场景通过。最新 Linux 隔离网络 414 个、日志压力 20 轮共 500 个、真实 systemd / polkit 3 个、Windows 164 个 Go 通过事件分别记录，见[权限日志验收](docs/verification/linux-tun-logs.md)。本阶段未修改 Dart，Flutter 440 项属于前阶段。[安装续验](docs/verification/linux-tun-install.md)保留管理员安装、升级、卸载、持久回滚及三十次强杀恢复；独立 Debian 13 / systemd 257 / polkitd 126 已实际验证核心启动、日志、允许和拒绝授权及恢复，使用 VM-only 规则，未验证活动桌面认证弹窗。GUI 服务管理和正式分发仍待完成，公开 TUN 开关继续关闭；权限路径要求 Linux 6.5+。`bash tools/verify_linux_network.sh --permission-logs` 为 Linux amd64 root 隔离入口，需要网络工具、D-Bus、gnome-keyring 与 GNOME 设置后端，fixture 授权器使用私有挂载。[宿主接入](docs/verification/linux-tun-manager.md)和[实际转发](docs/verification/linux-tun-forwarding.md)保留原阶段范围，包括一次原因待调查的历史转发失败。

桌面默认以 960 × 640 逻辑像素居中打开，采用紧凑图标导航，可自由拉宽或最大化。概览一屏展示连接控制、出口、统计与延迟趋势；窄屏和较大字体保留自然滚动。深浅主题截图与尺寸核对见 [概览布局验证](docs/verification/README.md#概览一屏布局--2026-10-16)。

移动端使用独立的紧凑标题与底部五 Tab，不再叠加一行应用栏；导航入口仍可进入规则、连接和日志。首页收拢上传、下载和今日流量，完整 IP 可复制，长 IPv6 自动换行。393×852 普通字号含 iOS/Android 安全区已验证一屏显示，320 宽及大字模式自然滚动；布局截图与原生服务边界见[移动布局续验](docs/verification/mobile-layout-20261017.md)。

最新一轮按 Figma 校正概览信息层级、独立分组卡片、节点协议标签和控制尺寸；大窗口保留纵向结构，小窗口合并网络控制行。流量页已接入当前会话速度及 SQLite 按日统计，可查看今日、本周、本月。旧版本最后一天的累计用量自动保留；更早未记录的历史无法恢复。视觉对照、测试范围和剩余差异见 [界面还原与真实统计验证](docs/verification/ui-layout-and-traffic.md)。

流量页进一步加入持久的 15 分钟用量曲线、日/周/月汇总、保守归属排行及当前周期 CSV 导出。应用在前台时，各页面均继续采样；后台间隔在恢复采样时记账，不推算缺失时段。持续使用全局或直连模式的会话可以归属到目标；规则模式、切换模式后的会话和旧版数据明确计入未归属。曲线区分无记录与已记录的零用量，点选或悬停可看数值；手机汇总使用一张紧凑卡片。schema 6 保存独立的会话检查点，避免重启及迟到样本重复累计；证据与限制见[持久流量验收](docs/verification/traffic.md)。

节点列表进一步补齐 Figma 的独立地区标识与两行名称布局，解决 Windows 将订阅旗帜显示为小号字母的问题。地区取自节点标注，未知时显示地球；原始订阅名称保留，悬停可查看服务器地址。移动端将协议与地区放在第二行，搜索支持中文地区和地区代码。截图与验证见 [节点地区标识校准](docs/verification/node-region-ui.md)。

节点支持收藏，订阅节点可设置本地别名、隐藏并恢复；这些设置在订阅刷新后保留，不改变服务商的连接参数。分组下拉同时提供「全部节点」「仅收藏」「已隐藏」视图。工具栏「测速」测试当前筛选列表，节点菜单可单独测试；最多 3 个并发，可取消，独立测试不会切换或关闭当前连接。这里测量经节点访问 HTTPS 204 测试站的耗时，不是下载带宽。隐藏节点后会清除后续选择，但当前连接和已有规则、代理链仍可继续使用。数据库自动升级到版本 5，详细证据与公网测试边界见[节点管理与测速验收](docs/verification/node-management.md)。

设置按通用、外观、网络、核心引擎、更新和关于六类组织；移动端点击分类进入详情，左上角返回。外观支持深浅主题、跟随系统、紧凑/标准密度、文字缩放与减少动效；密度在保存成功后立即应用，失败保留原值。网络可选择系统 DNS、HTTPS 加密 DNS、自定义 HTTPS/UDP、引导 DNS、IPv6 解析和本地混合端口。保存前经独立 sing-box 校验，保存不会打断连接，下次连接或在核心页确认重启后生效；重启保留原活动目标与规则。解析测试实际查询 example.com，可取消且不更改系统 DNS。核心引擎内的[高级配置](docs/verification/advanced-config.md)支持受控 YAML/JSON 覆盖、校验后确认应用、恢复上一版和导出；在线应用保留活动目标，失败恢复原连接。当前版本从 pubspec 生成，关于页提供实际字体与核心许可；Windows 通用系统集成与应用更新已接入。截图和真实 Windows 证据见[设置验收](docs/verification/settings.md)、[密度验收](docs/verification/density.md)与[应用更新验收](docs/verification/app-updates.md)。

Android 已接入 Keystore 凭据、原生系统隧道、前台服务、DNS 测试、后台会话恢复和原快照重连；首页自动启用隧道，切到后台保留连接。实时连接、单条/全部关闭、脱敏日志、持久采集和 CSV 已接入；导出通过系统文件保存器选择位置，实际写入、取消及页面关闭已验证，见[系统文件保存](docs/verification/android-documents.md)。通用设置新增默认关闭的启动自动连接、连接状态通知和订阅到期提醒；手动断开后返回前台不重连，到期通知可进入分组，见[自动连接与系统提醒](docs/verification/android-startup-notifications.md)。本机认证代理 IPv4 / IPv6 / DNS、后台及低内存持续传输通过，Flutter 界面真实关闭和文件写入也已验证；可视化双跳保存、概览连接、反向链、三模式、在线配置及失败恢复另有 9 次真实响应；同一系统隧道的 Wi-Fi / 蜂窝 / 断网恢复及手动断开也已通过，见[配置与切网验收](docs/verification/android-configuration.md)。真实订阅、真机授权和真机切网仍待验证。移动首页按 Figma 使用独立连接按钮、目标卡片、完整模式选择和设置入口；主页面、连接、日志及通用设置深浅主题已有 16 张 Android 渲染截图，44 个 SVG 与当前 Figma 原生导出一致。0.1.0+3 的本地 Debug 签名预览包为 `build/RainLink-0.1.0+3-android-debug-preview.apk`。构建、证据及未完成边界见 [Android 验收](docs/verification/android.md)和[Android 遥测验收](docs/verification/android-telemetry.md)。

## 开发

基线：Flutter **3.27.4** / Dart **3.6.2**，Go **1.25.5**。版本记录在 `.fvmrc`、`.go-version`，Dart 依赖提交锁文件。可使用 FVM 或自行安装 SDK；脚本支持 PATH 中的 Flutter，也支持 `FLUTTER_ROOT` 或 `-FlutterRoot` 指定 SDK。

Windows 需要 Visual Studio 2022 的「使用 C++ 的桌面开发」及 Windows SDK。

```powershell
# 仓库根目录，Flutter 已在 PATH 时无需 -FlutterRoot。
./tools/dev.ps1 run
./tools/dev.ps1 prepare # IDEA 启动前任务：校验内核并构建 Go 宿主，无需 Flutter SDK 参数。
./tools/dev.ps1 check
./tools/dev.ps1 smoke
./tools/dev.ps1 build

# SDK 不在 PATH 时：
./tools/dev.ps1 run -FlutterRoot '你的 Flutter SDK 目录'
```

`run` 先校验固定核心并构建宿主，再启动 Flutter；`check` 执行格式、静态检查与单元/组件测试；`smoke` 在真实桌面应用中验证宿主通信和主题落盘；`build` 生成 Windows x64 Release 目录，并放入宿主、核心及核心许可证。运行时保留完整目录。额外的连接与异常恢复检查见验收文档。

核心基于 sing-box **1.12.25**，Windows amd64 与 Linux amd64 分别锁定二进制 SHA-256。Windows / Android 的证书指纹扩展为 **1.12.25-rainlink.1**，Linux 桌面增加托管 TUN 的版本为 **1.12.25-rainlink.2**。`tools/core.lock.json` 固定上游与依赖校验值、Go 1.25.5、修改位置和构建标签；`tools/setup_core.py` 从经校验的源码构建并核对结果。默认构建当前平台，可指定 `--platform linux-amd64`。sing-box 使用 GPLv3，各平台输出目录包含 LICENSE 和对应源码 `sing-box-source.zip`；扩展说明见 [native/core](native/core/README.md)，上游为 [SagerNet/sing-box v1.12.25](https://github.com/SagerNet/sing-box/tree/v1.12.25)。

macOS / Linux 可执行 `bash tools/dev.sh run`，其他命令为 `check`、`smoke`、`generate`，需要对应平台的 Flutter 桌面构建工具。Linux amd64 已接入本地端口、Secret Service 凭据、核心退出保护及 GNOME / KDE6 系统代理与异常恢复。凭据依赖 libsecret 的 `secret-tool` 和可解锁密钥环；GNOME 需要 gsettings / dconf / gdbus 和 schemas；KDE 需要宿主旁的 Qt6 / KF6 ConfigCore 辅助程序，开发入口在 KDE 下自动构建。两套后端还需要会话总线和 pidfd；实际环境不满足时保留本地端口。`bash tools/verify_linux_session.sh --kde` 使用隔离配置和密钥环复验，依赖与范围见 [KDE 验收](docs/verification/linux-kde-proxy.md)。真实 Plasma / GNOME 桌面、KDE5、活动用户 TUN 授权与 Linux GUI 尚未验收；内部 TUN 和独立 systemd 安装验收见上文。Windows 有实机、Android 有隔离模拟器验收；macOS 宿主与 iOS 网络扩展仍未完成。

## 目录

```text
app/lib/
  app/             启动依赖、路由、独立桌面和移动导航
  application/     基于领域接口的状态与用例
  design_system/   语义主题与共用组件
  features/        页面与后续功能模块
  domain/          连接模型、CoreGateway、偏好接口
  data/            Drift 数据库与偏好仓库
  platform/        桌面宿主适配、窗口、移动端能力边界
native/host/       Go 宿主与协议检查
tools/            开发、检查、构建脚本
docs/             设计资料、开发方案、接口说明
```

修改 Drift 表后执行 `./tools/dev.ps1 generate`（或 `bash tools/dev.sh generate`），提交生成的 `.g.dart`。SDK 路径、数据库与构建产物不进入版本控制。应用已打包 Inter、Noto Sans SC 和 Roboto Mono 字体；界面图标与 Logo 使用 Figma 原生导出的 SVG，资源来源见 [导出清单](design/exports/runtime-assets/README.md)。

桌面快捷键：`Ctrl/Cmd + 1…8` 切换页面。宽窗口显示完整侧栏，窄桌面显示图标导航。默认保持未连接；打开系统代理选项后，在连接时生效。Windows 通用设置支持当前用户开机启动、启动时自动连接、托盘及连接通知。关闭窗口默认先断开与恢复再退出，也可选择保留到托盘；托盘菜单的「退出 RainLink」始终先确认网络恢复。关闭托盘图标会先恢复窗口，并关闭托盘关闭行为与通知。自动连接使用上次保存的选择、模式和系统代理选项；开机启动与自动连接都默认关闭。原生验收及通知边界见[设置验收](docs/verification/settings.md)。

Windows TUN 已接入概览开关，可与系统代理同时使用一个核心。连接中切换会保留原活动节点/代理链、规则和网络配置重连；启用失败时尝试恢复原连接。普通界面通过独立权限进程申请管理员授权，核心校验、网卡和路由确认成功后才提交状态；断开、取消、关闭和进程异常均清理本次接管。真实 TCP、UDP、DNS 及 Windows 原生 UI 证据与未测边界见 [TUN 验收](docs/verification/tun.md)。

Windows「设置 → 通用」支持订阅到期提醒，默认关闭；提前 3 天内及到期时分别提醒一次，通知只显示数量。续期按新有效期判断，未提供有效期不提醒，关闭托盘同时停用提醒。应用运行时检查，正常重开保留去重记录；系统接收、记录失败重试、点击回调和布局边界见 [到期提醒验收](docs/verification/subscription-expiry.md)。

Windows「设置 → 更新」支持稳定/预览渠道、可取消下载、SHA-256 校验和确认安装重启，自动检查默认关闭。安装前恢复网络并等待后台任务；新版本必须完成本地数据初始化与首帧确认，失败恢复原程序和数据库。0.1.0+3 新增持久事务记录及独立启动器，强杀 updater 后下次打开自动恢复，提交后保留新版本数据。当前在线包要求复用同一启动器；启动器变更或旧布局迁移需完整手动升级。生产源尚无可用发布版本，本地包未发布；物理断电、签名安装和卸载尚未验收。使用与真实验证见[应用更新验收](docs/verification/app-updates.md)与[中断恢复验收](docs/verification/app-update-recovery.md)。

- [开发方案](docs/DEVELOPMENT_PLAN.md)
- [当前宿主接口](docs/HOST_PROTOCOL.md)
- [架构评估与优化](docs/ARCHITECTURE_REVIEW.md)
- [两端独立布局与修改入口](docs/UI_LAYOUTS.md)
- [框架验证与运行截图](docs/verification/README.md)
- [设计规范](DESIGN.md)
- [代码规范](AGENTS.md)
