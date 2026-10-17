# RainLink 主要 UI 与实现清单

读取日期：2026-10-15。来源：当前连接的 Figma 文件 RainLink，Bridge 标识 `unsaved-mv9fbgep-e9d7ijqk`。本清单覆盖桌面 12、移动 11 个产品画面；截图均为本次通过 Bridge 新导出。桌面先实现，五平台共用领域模型与设计系统。

## 桌面端：首期

| 页面 / 节点 ID | 页面结构与主要交互 | 组件和数据依赖 | 验收重点 |
| --- | --- | --- | --- |
| [概览](ui/desktop/dashboard.png) `2:17066` | 连接卡、选组、系统代理/TUN、三模式、出口、速度/今日流量、质量、延迟趋势、节点健康、最近连接 | DesktopShell、ConnectionCard、CaptureControls、ModeSelector、EgressCard、MetricCard、LatencyChart、HealthList；CoreGateway 和统计仓库 | 所选与实际出站区分；权限/取消/超时；真实出口；质量指标有定义 |
| [节点](ui/desktop/nodes.png) `2:17478` | 全分组搜索、分组条、节点表、添加、代理链、测速、收藏和菜单 | NodeToolbar、GroupTabs、NodeTable、ProtocolBadge、LatencyBadge、NodeMenu；节点/覆盖属性、探测服务 | 选择不连接；搜索多个关键词取交集；来源控制编辑、隐藏和删除 |
| [分组](ui/desktop/groups.png) `2:17974` | 紧凑分组行、订阅流量/到期、选中、更多、进入节点 | GroupRow、UsageMeter、ExpiryBadge、GroupMenu；订阅/组/组内记忆 | 点行选组与右侧进入分离；未提供可空；手动归组不被订阅更新覆盖 |
| [规则](ui/desktop/rules.png) `2:18316` | 全部/域名/IP 筛选、规则表、添加/编辑/删除与优先级 | RuleFilter、RuleTable、RuleEditor、ConfirmDialog；规则仓库/配置编译 | CIDR/域名校验；组目标引用；兜底规则与模式真实生效；应用失败回滚 |
| [连接](ui/desktop/connections.png) `2:18738` | 总量、代理/直连、累计传输、搜索、暂停、关闭单条/全部、导出 | ConnectionSummary、ConnectionFilter、ConnectionTable；连接事件/核心控制/文件服务 | 视图暂停不停止采集；连接 ID 对应真实关闭；进程未知不造值 |
| [流量](ui/desktop/traffic.png) `2:19136` | 日/周/月、总量/上下行、趋势、排行、CSV | PeriodSelector、TrafficSummary、TrafficChart、UsageRanking；持久聚合 | 计数器重置、跨日、时区和重复采样；归属数据可靠；真实文件 |
| [日志](ui/desktop/logs.png) `2:19439` | 搜索、等级、暂停、清空确认、导出、保留提示 | LogToolbar、VirtualLogList、ConfirmDialog；日志服务/脱敏/文件服务 | 搜索与暂停有界；秘密遮蔽；容量及保留期限；导出真实结果 |
| [设置](ui/desktop/settings.png) `2:19743` | 左侧通用/外观/网络/核心引擎/更新/关于；局部详情与高级配置 | SettingsShell、SettingRow、ToggleRow、SelectRow、ThemePreview、DnsEditor、ConfigEditor、UpdateCard | 偏好持久化与即时主题；网络校验/确认/回滚；版本和更新来源真实 |
| [添加](ui/desktop/import.png) `2:20702` | 居中弹窗：订阅/单节点、自动更新、协议表单、高级参数、错误和重试 | AddProfileDialog、SubscriptionForm、8 种 ProtocolForm、ValidationMessage | 订阅自动命名成组；单节点进未分组；取消不残留任务；成功不连接 |
| [代理链](ui/desktop/chain.png) `12:30711` | 链名称、路径、跳点卡、排序/更换/移除、测试、保存并选中 | ChainEditor、HopCard、NodePicker、ChainTestResult；链仓库/隔离测试/配置编译 | detour 顺序；至少两跳；UDP/QUIC 兼容性；失败跳点；测试过期 |
| [移动节点](ui/desktop/move-node.png) `14:79433` | 分组目标选择、取消 | MoveNodeDialog；节点来源与归组事务 | 仅未分组的手动节点；移动不改来源/收藏，不影响当前活动快照 |
| [订阅信息](ui/desktop/subscription.png) `23:54186` | 当前订阅套餐、上下行/剩余、到期、更新时间、更新/编辑/删除 | SubscriptionDialog、UsageMeter、ExpiryBadge；套餐可空值/更新事务 | 只显示当前订阅；失败保留旧数据；删除时手动节点退回未分组 |

## 移动端：第二期

| 页面 / 节点 ID | 与桌面共用的业务 | 移动适配与差异 |
| --- | --- | --- |
| [首页](ui/mobile/home.png) `2:22537` | 连接状态机、模式、选择、出口、速度、今日流量 | 独立 MobileShell；五 Tab；iOS/Android 网络接管授权行，调用原生隧道服务 |
| [节点](ui/mobile/nodes.png) `2:22669` | 搜索、组记忆、节点权限、测速、链入口 | NodeCard 替代表格；独立 44 高搜索；一级 Tab 不带伪返回；操作命中至少 44 |
| [分组](ui/mobile/groups.png) `2:22877` | 自动成组、用量/到期、组选择和节点入口 | 订阅行最小 108、未分组 66；长文和大字允许增长；更多和箭头独立命中 |
| [流量](ui/mobile/traffic.png) `2:23007` | 时间范围、汇总、趋势和导出 | 手势/点选 Tooltip、系统分享；进程归属不可靠时展示节点/出站排行 |
| [设置](ui/mobile/settings.png) `2:23130` | 偏好、主题、DNS、核心、配置、更新和关于 | 自动连接/通知首屏；分类进入详情；原生授权/安装渠道决定可用操作 |
| [快速选择](ui/mobile/quick-select.png) `2:23425` | selectedTarget、每组上次节点 | 从首页进入的选择路由，返回保留来源；选择仍不连接 |
| [DNS](ui/mobile/dns.png) `2:23923` | DNS 模型、校验、测试、保存和回滚 | 复用设置详情业务；键盘避让、安全区、可滚动表单和固定操作区 |
| [代理链](ui/mobile/chain.png) `12:31009` | 链模型、排序、跳点选择、能力校验和测试 | 单列 HopCard；操作至少 44；NodePicker 使用移动弹层，避免完整复制桌面页面 |
| [添加](ui/mobile/import.png) `2:23573` | 订阅/协议表单、解析/事务、取消和重试 | 底部弹窗、相机扫码/拒绝/返回粘贴；键盘出现时滚动正文，操作区保持可见 |
| [移动节点](ui/mobile/move-node.png) `14:79814` | 归组约束与事务 | 底部选择层；取消/遮罩返回原列表位置 |
| [订阅信息](ui/mobile/subscription.png) `23:55019` | 单订阅详情、更新/编辑/删除和旧数据保护 | Sheet 高度跟随可用空间，支持长内容和安全区 |

## 需要真实实现的代表性状态

| 模块 | 已读取的代表性设计状态 | 实现策略 |
| --- | --- | --- |
| 连接 | 未连接、连接中、已连接、断开中、详情、检测中、失败、超时、授权、拒绝、首次使用 | 显式状态机 + 系统/核心事件；取消和失败有回滚 |
| 添加 | 订阅空/已填、地址错误、获取失败、导入/重试、成功、8 协议和高级字段、字段错误、扫码/相机拒绝 | 真实表单和异步任务；不按示例关键词硬切变体 |
| 分组/订阅 | 选组、空、详情、编辑、删除确认、更新中、失败、更新成功、删除成功 | 数据驱动；每个订阅独立任务/错误，不复制整页 |
| 节点 | 收藏、菜单、手动编辑、订阅说明、删除/隐藏确认、保存结果、搜索无结果 | 来源权限 + 本地覆盖 + 事务；选择与连接分离 |
| 代理链 | 默认、倒序、单跳、添加/更换、测试中、失败、通过、已选中 | 有序模型和配置摘要；测试结果不跨修改复用 |
| 规则 | 全部/域名/IP、添加/编辑、保存、删除确认/结果 | 任意输入的编辑表单和核心校验 |
| 连接工具 | 全部/代理/直连、暂停、搜索/无结果、关闭/确认关闭全部、导出 | 真实连接快照、控制命令及文件写入 |
| 流量 | 今日/本周/本月、三个选点状态、导出 | 连续真实时间数据、单位和时区一致 |
| 日志 | 全部/信息/警告/错误、搜索/无结果、暂停、确认清空/结果、导出 | 有界采集、视图缓存、脱敏和真实文件 |
| 设置 | 分类与详情、开关/选择器、主题、DNS 错误/测试/保存、核心确认/结果、更新、YAML/JSON 校验 | 偏好仓库、配置事务和平台更新适配 |

66 组、549 变体包含不同端、母版和历史组件，数量不等于独立功能数。产品实现将这些归并为少量可复用组件、状态模型和平台能力；[原始变体清单](component-states.json)保留可追踪性。

## 视觉总览与边界基准

- [桌面：概览、节点、分组、规则](ui/desktop-main-a.png)
- [桌面：连接、流量、日志、设置](ui/desktop-main-b.png)
- [桌面：弹窗与代理链](ui/desktop-dialogs.png)
- [移动：首页、节点、分组、流量](ui/mobile-main-a.png)
- [移动：设置、快速选择、DNS、代理链](ui/mobile-main-b.png)
- [移动：三个弹窗](ui/mobile-dialogs.png)
- [1100 宽浅色桌面](ui/acceptance/desktop-light-1100.png)
- [360 宽浅色手机](ui/acceptance/mobile-light-360.png)
- [大字、长名称、IPv6](ui/acceptance/mobile-large-text-ipv6.png)
- [键盘与弹窗滚动](ui/acceptance/mobile-keyboard.png)

弹窗独立导出包含设计中的透明区域，合成图采用暗色底呈现；应用中按当前页面叠加真实遮罩。静态截图用于复核视觉，系统行为由真实运行验收证明。
