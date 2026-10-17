# Linux TUN 普通宿主接入验收

2026-10-17：普通 `rainlink-host serve` 已接入 Linux TUN 的凭据读取、节点/链/规则编译、连接、状态观察、连接记录、模式切换、系统代理与确认断开。使用普通 UID、真实 Secret Service、root guardian 和锁定核心，14 个完整宿主场景通过。**真实 systemd / polkit 弹窗和安装管理尚未验收，公开 Linux `tun` 能力继续为 false。**

记录：[证据及源码摘要](linux/manager-evidence.json)、[完整测试目录](linux/manager-tests.json)、[完整宿主日志](linux/manager-lifecycle-tests.log)、[源站与完整网络快照](linux/manager-forwarding-state.json)。前阶段的[私有客户端与转发验收](linux-tun-forwarding.md)保留当时的范围和哈希。

## 接入行为

普通宿主从用户的 Secret Service 解密各节点凭据，按密文修订组装内存请求；权限服务只接收受控域模型。节点、链上每一跳和额外规则目标都经过身份绑定校验，凭据、API 密钥不进入 argv、磁盘配置、日志或 Flutter 回执。单节点快照保留桌面契约的公开节点信息并清空 credential；移动编译器原有的更小快照不变。

权限服务与直接子进程分别管理。普通宿主复用现有核心 API 读取遥测、连接记录和切换模式，TUN 观察使用权限服务分配的私有资源标识，同时核对接口、两种地址族路由与全部托管规则。损坏一条规则后，即使 API 仍可访问，也显示失败并保留会话标识。

正常断开必须收到 root 的完整恢复回执。连接丢失、停止取消或未知恢复状态会保留失败会话；重试只有在原 guardian 确认退出、root 观察到独占锁空闲且恢复 journal 已退役后成功。只读 `idle` 请求不运行恢复、不结束进程、不修改路由，也不会请求第二次系统授权。未完成启动同样保留恢复待确认状态。

socket activation 的 socket 创建者可能是 systemd。客户端先通过只读 `hello` 获取真实 guardian 的 PID/start/boot，再发送 start，避免将监听者身份当作本次 guardian。中断启动的恢复确认先等待这个身份退出，不能用“此刻还没有 journal”推断不会发生稍后的启动。

私有客户端停止至多 28 秒，之后必要的 guardian 退出观察和只读确认各有 3 秒边界。普通宿主断开操作时限为 45 秒，Flutter 对断开单独等待 50 秒；普通读取仍为 25 秒。超过边界保留失败，不伪造恢复成功。

## 实际验收

环境为 WSL Linux 6.6.87.2、Alpine 3.22.2 amd64、Go 1.25.5。mount / PID / network namespace、`/run`、用户目录、D-Bus 和密钥环均隔离；代理及原点位于第二个 network namespace。systemd 的连接传递由 fixture 模拟，pkcheck 使用合成授权器，Secret Service 和网络核心为实际进程。未使用用户订阅、真实节点凭据或既有数据库。

| 场景 | 实际检查 |
| --- | --- |
| 权限服务未安装 | 复用原宿主回归；拒绝系统代理/TUN，本地端口真实传输、模式与 EOF 清理保持 |
| 正常停止 | 双栈 TCP/UDP 回显、遥测、连接名称、模式、DNS、重复断开与 idle |
| 双跳链与规则目标 | 三个分别加密的节点；IPv4 经过双跳链，IPv6 匹配独立规则节点；修订与跳点绑定保持 |
| 系统代理与 TUN | GNOME 真实 dconf 后端，同时启用、独立切换系统代理、TUN 保持，最后恢复原配置 |
| 公共通道 EOF | 普通宿主清理后退出，核心与网络恢复 |
| 宿主强杀 | root 观察调用方退出，独立系统代理保护与 TUN 恢复 |
| guardian 强杀 | 独立 watchdog 恢复，宿主保留失败会话，root 确认后退役 |
| 核心强杀 | 失败状态保留原会话，权限服务恢复后允许确认断开 |
| watchdog 强杀 | guardian 结束本次捕获并恢复，宿主确认后断开 |
| 停止取消与重试 | 暂停 guardian、取消停止；不得报告 idle；恢复 guardian 后重试成功 |
| 策略损坏 | 精确删除本次租约的一条规则，观察为 failed，断开恢复其余规则 |
| 授权拒绝 | 固定拒绝码，无核心或网络变更 |
| 授权等待取消 | 已到达授权器后取消，保留未确认状态，原 guardian 退出后确认恢复 |
| 错误凭据身份 | 另一节点的密文不能用于本次节点，连接被拒绝 |

十个连接场景均执行实际数据请求；其中双跳链场景验证 TCP4/TCP6，其余九个验证 TCP4/TCP6/UDP4/UDP6。请求直接使用 OS socket，不使用 mixed 端口。目的服务按真实来源地址拒绝绕过代理的连接，确认 TCP4/TCP6 各 10 次、UDP4/UDP6 各 9 次，拒绝直连 TCP/UDP 各 20 次。直连模式下的四种 DNS 请求均被 TUN 截获，共 40 次实际解析。

每个场景完整接口、路由与规则均与开始前逐字段相同；核心/watchdog 退出、journal 删除。第二 namespace 销毁后完整网络与创建测试网线前相同。原 authorizer 与安装文件内容及 metadata 保持；父 namespace 全量比较通过，退出后没有 fixture namespace 进程残留。

| 本轮检查 | 结果 |
| --- | --- |
| Linux 网络、IPC、恢复、私有客户端、完整宿主 | 359 个通过事件、111 个顶层通过事件，含重复与子项 |
| 完整宿主 | 14 个场景通过 |
| Windows 锁定核心回归 | 164 个通过事件；3 项修改系统代理的显式条件测试跳过 |
| Flutter 全量与静态分析 | 440 项通过，无分析问题 |
| Go vet | Linux amd64 / arm64、Windows amd64 通过；arm64 未运行 |
| 格式与脚本语法 | gofmt、Dart format、shell 和 Python 通过 |

前阶段的完整 GNOME/KDE 244 事件没有整套重跑；本轮只通过完整宿主新增验收了 GNOME 系统代理与 TUN 共存。历史转发 120 次压力结果不重复计入本轮。

## 修正及边界

保留[首次夹具失败](linux/manager-history-attempt-1.log)：测试错误地通过只支持结束信号的生产恢复接口发送 SIGSTOP。改用 fixture 自己持有的 exec.Cmd 进程句柄；没有放宽生产接口。

保留[收尾时序失败](linux/manager-history-attempt-2.log)：journal 已退役时 guardian 可能仍在结束，立即重试曾返回“仍在退出”。现在使用固定进程身份和 pidfd 等待，最多 3 秒，随后再请求只读确认。暂停 guardian 的失败断言、原身份保留和全部网络相等断言均保留。修正后的 14 场景整体通过。

前阶段有一次转发失败因为旧夹具只输出子进程首行而没有具体断言；该历史问题仍待调查，见[原记录](linux-tun-forwarding.md#修正与复验)。本轮通过不等于已定位该问题。

复验：Linux amd64 root QA 主机可运行 `bash tools/verify_linux_network.sh --managed-host`，除原网络依赖外需要 D-Bus、gnome-keyring、dconf/gsettings 和 GNOME schemas。它在私有挂载中运行合成授权器；不会覆盖主机原 pkcheck。Windows/WSL 本轮使用缓存包构造临时 rootfs，再运行同一 namespace fixture。`python tools/finalize_linux_manager_evidence.py` 只校验与封装已有原始证据，不执行测试。

剩余包括真实 systemd / polkit、安装/升级/卸载、权限核心日志传输、真实 Linux GUI、切网/休眠/注销、ARM64 与 race detector。macOS/iOS 及全页面 Figma 对照继续开发。本轮没有修改 UI 画面或图标，没有重新打包 Windows 0.1.0+4，也没有操作 FlClash、其服务或用户手机。
