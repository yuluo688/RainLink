# Linux 首页 TUN：三模式验收与暂停检查点

2026-10-21，按用户要求暂停开发、提交并推送当前进度。本轮只修改两个 Linux QA fixture，产品源码未变；完整五平台与全页面视觉目标仍未完成。前轮范围保留在[首次暂停记录](closeout-20261021.md)。

## 测试网络修正

原测试源站与 SOCKS/DNS 入口均使用 `10.77.0.2` / `fd77::2`。当前锁定版本的 sing-tun 保留直连网段路由，使测试请求绕过隧道，不能据此判断代理模式。入口地址保持原样，TCP/UDP 源站移至 namespace 的独立地址 `10.78.0.2` / `fd78::2`，DNS 返回新地址，让源站请求经默认路由进入 TUN。

两族测试默认路由统一使用 metric 1：Linux 会将 IPv6 metric 0 变成 1024，优先级低于 VM 的 metric-100 RA 路由。建立测试网络前拒绝已有 metric ≤1 的默认路由，不覆盖环境路由。

本轮在同一隔离 VM 中先断开并确认恢复，再应用上述拓扑继续验收。修改后的 guest 启动脚本通过 Bash 语法检查，但尚未从全新 VM 整体重跑；不把已完成的会话验收描述为新脚本的全新启动验收。

## 实际产品验收

Debian 13 隔离 VM `rainlink-tun-product-20261021-02` 中，使用完整 Release 包、普通 GUI 用户与独立流量 UID。通过真实设置页系统密码授权安装，服务回读为就绪；实际添加弹窗保存虚构 SOCKS5 节点，网络页保存自定义 DNS 和 IPv6，首页接受系统授权建立 TUN。测试不读取用户订阅、数据库或真实凭据。

下列客户端回执全部通过，并已与[源站原始记录](linux-tun-product/modes-20261021/origin-v2-receipts.jsonl)逐项匹配 nonce 或 DNS 查询名、类型。TCP/UDP 同时核对源站观察到的双栈源地址，DNS 核对 A/AAAA 返回地址。

| 场景 | 回执数 | TCP/UDP 结果 |
| --- | ---: | --- |
| 修正拓扑后的连接前基线 | 4 | 双栈直连 |
| 默认规则模式 | 6 | 私网规则直连，DNS 劫持通过 |
| 全局模式 | 6 | 双栈代理，DNS 劫持通过 |
| 直连模式 | 6 | 双栈直连，DNS 劫持通过 |
| 保存 IPv4 规则后、尚未重连 | 6 | 保留旧会话规则 |
| 保存双栈规则后、尚未重连 | 6 | 保留旧会话规则 |
| 重连应用自定义双栈规则 | 6 | 双栈代理，DNS 劫持通过 |
| 连接中关闭 TUN | 4 | 原始流量双栈直连 |
| 连接中重新授权开启 TUN | 6 | 双栈代理，DNS 劫持通过 |
| 正常断开后 | 4 | 双栈直连 |
| 活动连接关闭窗口前 | 6 | 双栈代理，DNS 劫持通过 |
| 活动连接关闭窗口后 | 4 | 双栈直连 |

共 12 组、64 个客户端回执，详见[机器可读检查点](linux-tun-product/modes-20261021/checkpoint.json)。规则编辑后的旧会话继续使用旧快照，重连后才应用 `10.0.0.0/8`、`fc00::/7` 指向当前所选目标的规则，与界面提示一致。

七份恢复快照均重新与[连接前内核基线](linux-tun-product/modes-20261021/before-capture.json)核对：规则重连前、连接中关闭 TUN、正常断开、活动连接退出及本次暂停的三个阶段。网卡、地址、IPv4/IPv6 全部路由和规则一致，只忽略独立倒计时的租期字段。[活动连接退出恢复](linux-tun-product/modes-20261021/active-exit-restored.json)与[暂停后恢复](linux-tun-product/modes-20261021/pause-session-stopped.json)保留原始结果；实际窗口关闭正常退出，VM 服务卸载和外层自然退出均为 0。

实际画面：[自定义规则连接](linux-tun-product/modes-20261021/custom-rule-traffic.png)、[连接中关闭 TUN](linux-tun-product/modes-20261021/tun-off-connected.png)、[重新开启](linux-tun-product/modes-20261021/tun-on-traffic.png)、[暂停时未连接](linux-tun-product/modes-20261021/pause-disconnected.png)。早期同网段拓扑的失败和一次弹窗未关闭时被遮罩拦截的操作不计入这 64 个回执，也不作为产品恢复失败证据。

## 检查与视觉范围

- `git diff --check`、Python `py_compile`、VM 内 `bash -n` 通过；[VM 检查回执](linux-tun-product/modes-20261021/pause-checks.txt)已保存。本轮未修改 Dart/Go，没有重跑上一检查点的 Flutter/Go 全量测试。
- Figma Bridge 已重新连接并读取桌面、移动、设置详情和设计系统。[44 个 SVG](linux-tun-product/modes-20261021/figma-assets.json)与当前运行资产逐字节一致，[26 个深浅色映射](linux-tun-product/modes-20261021/figma-color-check.json)一致；[原始变量](linux-tun-product/modes-20261021/figma-tokens.json)保留。本轮实际画面为 960×640 深色，1440×900、浅色及全部页面的实际渲染对照尚未完成，不能据图标和颜色一致声称全 UI 一致。
- [首次会话日志](linux-tun-product/modes-20261021/first-session-rainlink.log)仍有 `atk_socket_embed` critical。重开时确认 VM 缺少 AT-SPI 服务与 launcher，[重开日志](linux-tun-product/modes-20261021/rainlink.log)同时保留总线警告；缺包补装及警告定位尚未完成，没有通过屏蔽警告处理。

QA 包为 `build/qa/linux-gui/tun-product-acceptance/rainlink-preview.tar.xz`，`0.1.0+4`，32,508,860 bytes，SHA-256 `b2d6c34cfed17d7d37051ea371b08ef2ea8e000c5edc5963ceebc290083987b7`。沿用前轮完整包，开始时 653 项输入一致；随后修改两个 QA fixture，不能再声称当前全部输入与旧包逐字节一致。未重新打包、未覆盖默认 preview、未发布 Release。

恢复后优先验收服务停用/禁用后的真实 UI 能力刷新与“启用服务”修复，再处理 AT-SPI 环境及警告，并完成两种桌面尺寸、深浅主题与移动实际渲染对照。用户暂时没有 Mac，Apple 原生构建和授权仍待可用环境。
