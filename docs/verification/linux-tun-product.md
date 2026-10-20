# Linux 首页 TUN：暂停检查点

2026-10-21 最新补充：已完成完整产品三模式、规则重连、连接中开关与退出的 64 个双栈 TCP/UDP/DNS 回执及七次内核恢复核对，按用户要求暂停并正常关闭 VM，见[三模式验收与暂停检查点](linux-tun-product-modes.md)。服务失效修复、GTK 警告及完整视觉仍待继续。以下保留 2026-10-20 的原始验收范围，前次暂停见[首次暂停记录](closeout-20261021.md)。

2026-10-20，按用户要求暂停开发并保存代码。**接受授权后的完整产品 TUN 连接、代理流量与断开恢复尚未验收，本阶段不作为发行完成依据。**

## 已实现与实际范围

Linux 宿主仅在核心可信、已安装服务与当前构建一致、socket 已启用且活动时报告 `capabilities.tun=true`。检查只读，不授权或创建隧道。首页保留原 TUN 开关，服务不可用时提供设置入口；安装、卸载、失败和取消回读后刷新能力，刷新中或管理中禁用旧开关状态。文件一致但服务停用时显示「启用服务」。Linux 原生服务检查限 10 秒，桌面一次性状态调用限 20 秒，修复旧 5 秒等待在 TCG 安装/冷启动负载下失败的问题。

最终完整 Linux 包在全新 Debian 13 VM、普通用户、真实 systemd/logind/polkit 和 X11/Openbox/lxpolkit 会话运行，没有替换包内二进制：

- 首页进入设置、真实系统密码授权安装和状态回读通过，服务 `current/enabled/active`、宿主 `tun=true`，应用无需重启显示就绪。
- 实际添加弹窗保存并选择虚构 SOCKS5 节点；实际网络设置保存自定义 DNS 与 IPv6。测试脚本首次键盘输入丢失被校验拒绝，改用剪贴板后正常保存，最终截图保留。未使用用户订阅、数据库或真实凭据。
- 首页开启 TUN 并连接，出现真实系统授权窗口。首次等待结束后无内核残留；重试并以 Escape 取消授权后，双栈网卡、地址、全部路由和规则与接管前一致。独立 UID 的 TCP4/TCP6/UDP4/UDP6 四个源站回执仍为直连，客户端与源站记录均保留。
- 用户要求暂停后再次确认内核恢复，停止会话、卸载 VM 服务、删除测试网络并关机。guest cleanup 与外层执行均 exit 0；**此退出码仅证明上述阶段及清理，不证明未执行的成功连接。**

最终证据位于 [final-vm](linux-tun-product/final-vm/)，包括[服务](linux-tun-product/final-vm/service-current.json)、[宿主](linux-tun-product/final-vm/status-current.json)、[授权取消恢复](linux-tun-product/final-vm/after-authorization-cancel.json)和[暂停前恢复](linux-tun-product/final-vm/pause-kernel-restored.json)。早期根目录截图属于诊断或安装阶段，不计为最终成功连接。最终应用日志还出现一条 `atk_socket_embed` critical，保留原始记录，尚未定位；不能据旧阶段的严格退出结果宣称本次日志无警告。

| 检查 | 本次结果 |
| --- | --- |
| Flutter 全量 | 546 项通过，0 失败；[原始事件](linux-tun-product/flutter-tests-final.json) |
| 静态分析 | 无问题；[日志](linux-tun-product/flutter-analyze-final.log) |
| Linux Go 全包及 vet | 393 个通过、209 个跳过测试事件，14 包通过、5 包跳过；[事件](linux-tun-product/go-tests.json)；vet 通过 |
| Windows Go 全包 | 141 个通过、28 个跳过测试事件，5 包通过、7 包跳过；[事件](linux-tun-product/windows-go-tests.json) |
| Linux ARM64 / Darwin ARM64 | 宿主交叉编译通过，仅证明编译 |
| Python 工具 | 21 项通过、2 项按平台跳过；[日志](linux-tun-product/checkpoint-python-tests.log) |
| Linux 输入 | 构建时 652 项与当时工作区一致；[输入](linux-tun-product/source-inputs.json)、[结果](linux-tun-product/source-verification.json)。之后新增的只读内核快照 fixture 见[补充输入](linux-tun-product/supplemental-inputs.json) |

Go 事件包含子测试，不合并为独立测试数。概览与设置参考已从当前 Figma 重导出，[44 个 SVG](linux-tun-product/figma-assets.json)与运行资产逐字节一致；复查了 960×640 深色实际画面。本阶段最终 1440×900、浅色及全页面核对未完成，不声称逐像素一致。

收尾使用生成器重新生成 Drift 输出，再统一 84 个受影响 Dart 文件格式，格式检查无改动。格式整理后的共享回归与静态分析单独保存为 [测试](linux-tun-product/flutter-tests-checkpoint.json)和[分析](linux-tun-product/flutter-analyze-checkpoint.log)。本次没有重新打包格式整理后的源码，652 项输入记录仅对应前述已运行 QA 包，不能作为提交后源码的逐字节匹配证明。

## 产物与待续验

本轮 QA 包：`build/qa/linux-gui/tun-product/rainlink-preview.tar.xz`，0.1.0+4，32,505,460 bytes，SHA-256 `d3e9ea558ebec43fb187148f3bc2582fbbcbe4b1b5d34fb0c1f55359dcbb2683`。仅本地验收，**未覆盖默认 Linux preview 包，未发布安装包**。[机器可读检查点](linux-tun-product/checkpoint-tests.json)记录范围。

恢复后优先：接受授权后的首页真实 TUN 连接；规则/全局/直连三模式原始双栈 TCP/UDP/DNS；连接中开关、正常断开和窗口退出的精确恢复；停用/不同构建服务的能力刷新与修复；两种尺寸和深浅主题。此前独立宿主/权限服务证据不能替代完整产品 UI 验收。

macOS/iOS 原生构建及授权仍需要 Mac，当前无该环境。五平台完整交付与全页面 Figma 目标尚未完成。
