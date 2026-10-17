# 框架验证

2026-10-17 最新 Linux 续验：[普通宿主 TUN 接入](linux-tun-manager.md)完成真实密钥环、节点/链/规则、遥测、模式、共存接管与恢复确认；14 个完整宿主场景通过。当前 359 个 Linux、164 个 Windows Go 通过事件，440 项 Flutter 与静态检查通过，完整父网络与原安装文件保持。真实 systemd / polkit、安装管理与权限日志仍待完成，公开 Linux TUN 继续关闭；没有重新打包。以下各阶段保留原始范围和哈希。

2026-10-17 图标实时复核：[当前 Figma 原生资产核对](runtime-audit-20261017.md)重新导出 44 个 SVG，与应用逐字节一致；品牌完整 RGBA 像素、27 个原生 PNG 和 9 尺寸 ICO 通过。没有修改应用资产或重新构建安装包，完整页面布局仍待核验。

2026-10-17 最新 Linux 续验：[实际 TUN 转发与原生客户端](linux-tun-forwarding.md)完成隔离内核中的双栈 TCP/UDP/DNS，三轮通过；普通 UID 客户端六种生命周期各三轮，授权取消额外二十轮通过。343 个 Linux 网络/IPC 与 164 个 Windows Go 通过事件；原安装文件与完整父网络保持一致。公开 Manager、真实系统授权/systemd、安装及日志仍待接入验收，开关继续关闭。UI、图标和预览包未变。以下为历史阶段。

2026-10-17 Linux 权限阶段：[权限通信与 guardian](linux-tun-permission.md)加入真实 socket peer pidfd、受控协议、固定 polkit 调用及 watchdog 在线联动；七场景各三轮，共 21 次会话恢复通过。当时 229 个网络/IPC、244 个 GNOME/KDE、164 个 Windows Go 通过事件；早期 ESRCH 残留已复现修复，历史压力 80/80 通过。该阶段的真实系统授权、systemd、普通宿主与实际 TUN 转发尚未验收。

2026-10-17 Linux 自动恢复阶段：[独立 TUN 监控](linux-tun-watchdog.md)加入 root 专用 pidfd watchdog，原权限进程被强杀后自动停止绑定核心、清理规则并退记录；四种场景各 5 次通过。152 个网络恢复、244 个 GNOME / KDE、164 个 Windows Go 通过事件，静态检查通过。该阶段未确认的残留原因已在上方新阶段定位修复。

2026-10-17 最新 Linux 核心续验：[托管 TUN 与精确恢复](linux-managed-tun-core.md)加入 Linux 专有核心 `.2`，显式托管模式取消区间清理，16 条协议 242 规则在正常退出 / 强杀后由 guardian 恢复；启动冲突、同名网卡和后来所有者保留通过。120 个网络恢复、244 个 GNOME / KDE、164 个 Windows Go 通过事件及源码包独立复现、静态检查通过。生产权限 / TUN watcher 及实际转发尚未接入，Linux TUN 保持关闭。下方为各阶段历史记录。

2026-10-17 最新 Linux 资源验收：[TUN 租约与显式恢复](linux-tun-recovery.md)实现跨进程独占、持久记录及完整身份清理，真实隔离内核验证强杀后 16 条残留规则恢复、原守护进程退出后接续恢复、后来规则保留与歧义拒绝。111 个网络与恢复定向、244 个 GNOME / KDE、164 个 Windows Go 通过事件；生产权限 / TUN watcher、核心区间清理替换及实际 TUN 转发仍未接入，Linux TUN 保持关闭。未修改 UI 或生成安装包。

2026-10-17 最新 Linux 前置验收：[网络观察与 TUN 规则生命周期](linux-network.md)加入可取消、有界的 rtnetlink 读取，普通用户上游选择、扩展路由表与双栈策略规则通过；隔离命名空间实际验证正常退出清理和强杀核心后的 16 条残留规则。Windows 164 个 Go 回归事件通过。Linux TUN 权限与恢复尚未完成，开关仍未开放；本轮未修改 UI 或生成安装包。

2026-10-17 最新 Linux 续验：[KDE 系统代理与跨桌面恢复](linux-kde-proxy.md)接入真实 KConfig6 / libproxy 后端，GNOME / KDE 五种退出与崩溃场景、真实核心传输、旧版日志及用户配置保留通过。242 个 Linux、162 个 Windows Go 通过事件及 8 项 Flutter 状态协议测试、静态分析通过；真实 Plasma / GNOME 桌面、Linux TUN 与 GUI 仍待验收。本轮未生成新的完整安装包。

2026-10-17 最新续验：[订阅兼容确认与详情校准](subscription-compatibility.md)支持 sing-box JSON 节点、逐项安全原因及原弹窗确认，440 项 Flutter 全量、静态分析、八个原生视觉场景和 Windows 真实双跳通过。40 张截图覆盖双端深浅色及大字号，十个 Figma SVG 重新导出一致；三个现有 HY2 远程测速及经 HY2 订阅获取 / 解析成功，68 个兼容节点。下载器已接入活动本地代理，直连及两个 HTTP 节点的失败另存。最新 0.1.0+4 包与摘要见 [desktop-build.json](desktop-build.json)。下方保留历史验收范围。

2026-10-17 最新续验：[Windows 应用更新](app-updates.md)已接入固定发布源、渠道、可取消下载、摘要校验和安装交接。真实 Flutter AOT 隔离安装及启动失败后的程序/数据库回滚通过；全量 Flutter 329 项、4 项 Python 打包回归、56 张双端布局截图和 Release 实窗通过。生产源当前尚无可用发布版本，正式线上升级未验收；最新包和摘要为 [desktop-build.json](desktop-build.json)。

2026-10-17 续验：[订阅到期提醒](subscription-expiry.md)已接入 Windows 通用设置，默认关闭；真实系统提交、SQLite 写入失败重试、正常重开去重、回调恢复窗口并进入分组通过。当前全量 Flutter 为 303 项通过。各平台当前范围以[实现清单](../IMPLEMENTATION_STATUS.md)为准，下方保留早期验收快照。

最新验证：[Hysteria2 真实网络续验](hysteria2-network.md)（2026-10-16）：补齐 Windows Hysteria2 的上游接口选择、标准 IPv4 Fake-IP 处理和探测超时状态。真实机场已有 HTTPS、出口和流量成功记录，Release 窗口也取得台湾线路实际出口；多轮请求仍有间歇超时，未将所有线路标记为稳定通过。38 项 Go 测试事件通过，3 项写系统代理的显式测试跳过，Flutter 静态分析通过；原 68 个节点、原选择和主题保留。

前一轮：[Hysteria2 导入与真实核心验证](hysteria2.md)：138 项 Flutter 测试与静态分析通过。原订阅通过 Release 界面更新至 68 个节点，其中 Hysteria2 为 16 个。真实本地 QUIC / Salamander、错误认证和证书指纹校验通过；保留首次外网抽测超时的原始证据。

上一轮：[节点地区标识与列表校准](node-region-ui.md)：131 项 Flutter 测试、静态分析及 2 项 Windows 渲染测试通过，补齐独立地区标识、名称与地区对齐，修正 Windows 旗帜字形与移动窄屏布局。

前一轮：[界面还原与真实统计](ui-layout-and-traffic.md)，含概览、分组与流量的结构调整与统计存储验证。

以下保留早期框架阶段的验证快照；能力与布局以最新记录为准。

概览布局及 Figma 资源校准于 2026-10-16 复核；其他原生宿主与平台检查保留 2026-10-15 的验证记录。

环境：Windows x64，Flutter 3.27.4 / Dart 3.6.2，Go 1.25.5，Visual Studio 2022。当前屏幕 1920 × 1080、125% 缩放。

| 检查 | 结果 |
| --- | --- |
| Dart 格式与 Flutter 静态分析 | 通过，无分析问题 |
| Flutter 单元与组件测试 | 本轮 55 项通过，最终 UI 调整后相关 23 项再次通过（2026-10-16） |
| Go 格式、vet 与测试 | 通过，3 项测试 |
| Windows 原生集成测试 | 1 项通过 |
| Windows 真实子进程异常回收 | 4 个场景通过 |
| Windows x64 Release 构建与启动 | 通过 |
| 打包宿主与本次构建宿主 | SHA-256 一致 |

组件测试覆盖八个导航、代理链入口、快捷键、320 / 393 / 960 / 1100 / 1440 逻辑像素布局，以及主题写入失败时保持原状态。协议测试验证未知状态被拒绝、不可用适配器不会返回连接成功、改选保持活动快照。

架构优化新增主题并发顺序/失败恢复/销毁、宿主检查合并/取消/输出边界/晚到启动，以及概览局部重建的回归覆盖。真实子进程脚本验证 stdout/stderr 超限、超时、主动销毁后退出。测量方法、结果与边界见 [架构评估](../ARCHITECTURE_REVIEW.md) 和 [测量数据](architecture-metrics.json)。

异常与分支复查新增保存异常重试、程序 Error 传播、启动错误不被清理错误覆盖的测试。复查后的 35 项 Flutter 测试、静态分析和 4 个真实进程回收场景通过。

原生集成测试调用实际 Go 宿主，确认宿主就绪但连接能力关闭；通过界面保存主题，销毁应用并关闭数据库，再重新打开 SQLite 验证记录，最后恢复原主题。

Release 实际启动后确认窗口完整位于工作区内；早期宽窗口截图为 1800 × 960 物理像素，当前默认紧凑窗口为 1200 × 800 物理像素。以下图片来自实际运行应用，网络状态为未连接，未使用设计稿中的示例网络数据。

- [概览](windows-overview.png)
- [架构优化后的 Release 概览](windows-optimized-overview.png)
- [分组空状态](windows-groups.png)
- [自定义窗口栏：深浅主题与实际窗口操作](window-chrome.md)

## 概览一屏布局 · 2026-10-16

连接卡与网络控制并排，出口与三项统计横排，趋势卡占用剩余高度。空状态缩减留白，宿主提示并入趋势卡底部。其他页面保留原有滚动布局；较大字体和窄屏下，概览恢复自然滚动。

Windows Release 在 125% 缩放下实际打开并检查了深浅主题：

| 窗口逻辑尺寸 | 实际 Flutter 客户区 | 结果 |
| --- | --- | --- |
| 宽窗口 1440 × 768 | 1427.2 × 760.8 | 完整可见，无需滚动 |
| 默认 / 最小 960 × 640 | 947.2 × 632.8 | 完整可见，无需滚动 |

- [宽窗口 · 浅色](windows-overview-fit-light.png)
- [最小窗口 · 浅色](windows-overview-fit-compact-light.png)
- [宽窗口 · 深色](windows-overview-fit-dark.png)
- [最小窗口 · 深色](windows-overview-fit-compact-dark.png)

新增 7 项布局回归测试，检查五种桌面客户区内全部概览信息可见、概览没有滚动容器、模式切换与节点入口可操作，以及字体放大后的完整可达性。格式检查、静态分析和全部 49 项 Flutter 测试通过，Windows x64 Release 重新构建并启动。核对后已恢复原浅色主题和默认窗口，停留在概览。

画面展示当前真实的未连接及无遥测状态；本次验证不代表网络核心或出口检测已接入。

### 默认紧凑启动 · 2026-10-16

默认桌面启动尺寸改为 960 × 640 逻辑像素，居中打开并自动采用图标侧栏。未发送窗口缩放命令的启动核验得到 1200 × 800 物理外框、947.2 × 632.8 逻辑客户区；概览完整可见。实际点击最大化后，再点击还原，窗口回到相同紧凑尺寸。

本次 Dart 格式、Flutter 静态分析及概览 / 窗口控件的 24 项组件测试通过；Windows Release 已重新构建并启动，保留本机当前深色主题。其他平台的启动尺寸使用同一初始化代码，尚未在目标系统运行验证。

- [实际默认紧凑窗口](windows-compact-startup.png)

### Figma 资源与视觉校准 · 2026-10-16

界面图标、品牌与国家图标改用从 Figma 原生导出的 44 个 SVG；系统应用图标使用同一品牌节点导出的高清 PNG 生成。打包设计字体并修正中文变量字体的字重，统一侧栏、开关、模式选择器、设置分类栏、节点搜索工具栏和表头密度。保留 960 × 640 默认小窗与一屏概览。

- [本轮改动、验证与资源来源](figma-ui-alignment.md)
- [紧凑概览 · 深色](windows-figma-icons-compact-dark.png)
- [紧凑概览 · 浅色](windows-figma-icons-compact-light.png)
- [节点与搜索](windows-figma-icons-nodes-dark.png)
- [设置分类](windows-figma-icons-settings-dark.png)
- [代理链返回箭头](windows-figma-icons-chain-dark.png)

### 页面切换动画 · 2026-10-16

全部内容路由改为 180 ms 淡入和 8 逻辑像素上移，桌面导航与顶部固定，支持系统减少动画。23 项相关组件测试、静态分析、Windows Release 构建及实际切换核验通过。

- [动画说明与验证](page-transitions.md)
- [实际窗口录屏](windows-page-transition.gif)

### 两端独立布局 · 2026-10-16

桌面和移动端改为按平台选择独立布局，统一路由与业务状态。66 项测试、静态分析、格式检查及 Windows Release 构建通过，实际核对紧凑概览、节点与设置。移动端已进行组件测试，尚未真机验证。

- [布局文件与修改入口](../UI_LAYOUTS.md)
- [测试与 Windows 实际截图](platform-layouts.md)

复现命令见根目录 [README](../../README.md) 的 `check`、`smoke`、`build`。可执行文件位于 `app/build/windows/x64/runner/Release/rainlink.exe`，运行时保留同目录的 DLL、data 与宿主程序。

以上为框架阶段的历史记录；当前 Windows 已有核心与恢复验收，Android 原生网络及移动界面进展见 [Android 验收](android.md)。macOS、Linux 宿主和 iOS 网络扩展仍未完成。
