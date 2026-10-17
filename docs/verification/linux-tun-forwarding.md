# Linux TUN 实际转发与原生客户端验收

后续的普通 Manager、真实密钥环与 13 个完整宿主场景见[宿主接入验收](linux-tun-manager.md)。以下保留私有客户端阶段的结果、当时尚未接入的范围和源码摘要，不作为后续修改后的验收依据。

2026-10-17：隔离 Linux 内核中的 IPv4 / IPv6 TCP、UDP、DNS 实际转发通过三轮验证。普通 UID 65534 使用新增的原生客户端连接 root guardian；六种客户端生命周期各三轮，另有二十轮授权等待取消验证。**公开 Manager 尚未接入该客户端，真实 systemd / polkit 与安装管理仍待验收，Linux `tun=false` 保持不变。**

本阶段记录：[证据清单](linux/forwarding-evidence.json)、[完整测试目录](linux/forwarding-tests.json)、[运行日志](linux/forwarding-namespace-run.log)、[转发及完整网络快照](linux/forwarding-state.json)。[前一阶段权限验收](linux-tun-permission.md)保留当时的范围和哈希，不作为本轮新增源码的通过依据。

## 实际数据路径

运行环境为 WSL Linux 6.6.87.2、Alpine 3.22.2 amd64 和 Go 1.25.5。测试在独立 mount / PID / network namespace 内运行，并将代理及目的服务放到第二个 network namespace。它使用锁定的 Linux `.2` 核心，不是网络接口或转发逻辑的模拟。

普通用户以 OS 原始 socket 请求目的地址，经过 RainLink TUN、认证 SOCKS5 节点和目的回显服务；没有使用 mixed 端口或 HTTP 代理环境变量。目的服务按实际来源地址判断是否接受，直接从调用方 namespace 到达的请求会被拒绝，避免将直连误算为代理成功。地址、账号、DNS 和流量均为隔离测试数据，未使用用户的真实订阅、节点或既有数据库。

| 检查 | 实际断言 |
| --- | --- |
| TCP IPv4 / IPv6 | 两种地址均收到完全相同的回显 payload |
| UDP IPv4 / IPv6 | 两种地址均收到完全相同的回显 payload |
| 核心连接记录 | 四条存活连接均为 `tun/rainlink-tun`，出站包含 `proxy`，上传和下载均大于零 |
| DNS 截获 | 向不存在的 DNS 地址发送 TCP / UDP、IPv4 / IPv6 请求；全局和直连模式各四项，都得到配置解析器的实际答案 |
| DNS 上游 | 八个不同查询名，目的解析器计数至少八次，避免缓存掩盖未到达上游 |
| 直连拒绝 | TUN 开启前及切到 Direct 后共四个 TCP、四个 UDP 请求均被源站拒绝 |
| 会话恢复 | 核心退出、journal 删除，完整接口 / 路由 / 规则与连接前逐字段相同 |
| 测试网线撤销 | 第二 namespace 退出后，原有完整网络与创建 veth 前逐字段相同 |

最后一轮的四条连接各记录上传、下载 28 字节；目的服务各收到一条 TCP4、TCP6、UDP4、UDP6，另拒绝四个 TCP、四个 UDP，解析八次 DNS。三轮原始结果见 [转发日志](linux/forwarding-tun-forwarding-tests.log)。这证明功能路径，不代表吞吐量、丢包或公网稳定性已经测量。

## 原生客户端

`linuxipc.DialRootService` 逐级打开并检查 root 控制的目录，拒绝符号链接、可写祖先、非 root 所有者和非 socket。最终使用 O_PATH 固定 socket inode，再通过对应 procfs FD 连接，避免检查后重新解析路径。连接后继续以 SO_PEERCRED / SO_PEERPIDFD 认证 root 对端，要求 Linux 6.5+。

新增 `linuxTUNClient` 提供固定 `/run/rainlink/tun.sock` 入口，凭据只进入内存帧。它严格检查启动和停止回执、请求编号与接管状态；取消已完成的启动操作不会终止活动会话。并发停止只发送一次命令，只有明确的恢复成功回执才返回成功。EOF、服务退出、超时、无效回执与 `recovery_pending` 均保留失败，不冒充正常停止。

| 六种真实 root 会话场景 | 结果 |
| --- | --- |
| 正常停止 | 核心与资源恢复后确认成功 |
| 主动关闭 socket | 原生客户端保留服务中断错误，root 自动恢复 |
| guardian 被强杀 | 客户端识别 EOF，独立 watchdog 恢复 |
| guardian 暂停导致停止超时 | 客户端返回未确认恢复，恢复 guardian 后实际清理完成 |
| 授权拒绝 | 返回固定权限拒绝码，无核心、租约或网络变更 |
| 授权等待时取消 | 关闭通道、取消 authorizer，未产生接管 |

这六项各三轮，共十八次；取消另连续二十轮通过。十四种合成 IPC 场景检查错误编号、缺失结果、未知字段、未就绪、低权限端口、错误停止、恢复待定、服务丢失、主动伪造停止及并发/已取消的停止。合成回执只证明客户端边界，不作为真实转发证据。

## 修正与复验

真实取消测试发现：socket deadline 可能先于 context timer 发布状态，客户端此前误将已超时操作归为服务中断。现在同时保留 codec 的 `DeadlineExceeded` / `Canceled` 分类。保留 [修复前原始失败](linux/forwarding-history-native-cancellation-before.log)，没有放宽分类断言；本轮新增普通用户回归和实际授权取消压力验证。

第二 namespace 的最后一个进程退出后，内核可能延后撤销 veth；fixture 现在等待完整网络精确相等，最多四秒。该等待仅处理测试 namespace 的内核销毁，没有过滤差异。服务器清理先停止 accept，再关闭全部已登记连接并等待 worker；失败时同时结束该测试进程组，避免测试核心保留第二 namespace。

另有一次早期三轮转发中的第三轮失败，旧父测试只显示了失败子进程的首行，具体数据检查的原因尚未确定。现在展开读取失败详情，并保留 [该次失败原始日志](linux/forwarding-history-intermittent-before-diagnostics.log)。补充 [20 轮](linux/forwarding-stress-20-tests.log)及 [100 轮遇错即停](linux/forwarding-stress-100-tests.log)共 **120 / 120** 通过，两个完整父网络比较、测试进程清理和原安装文件保留均通过；未复现该失败。后续通过不能替代这次失败的根因定位；该项继续保留为待调查问题，不称为已经修复。

复验入口 `bash tools/verify_linux_network.sh` 需要 Linux amd64 QA 环境、root、iproute2、setpriv、unshare 和 TUN。fixture 将 `/run` 及测试安装文件隔离在私有挂载中，模拟 authorizer 和 helper 不改写原 `/usr` 文件。Windows / WSL 本轮通过独立临时 rootfs runner 执行相同 fixture。证据脚本为 `python tools/finalize_linux_forwarding_evidence.py`，它核对原始结果、完整快照、父网络、当前源码和产物摘要；不是再次运行网络测试。

| 本轮检查 | 结果 |
| --- | --- |
| Linux 网络 / IPC / guardian / 原生客户端 / 实际转发 | 343 个通过事件、109 个顶层通过事件，包含子项和重复 |
| 补充转发压力 | 20 + 100 = 120 / 120 通过，单独统计，不重复计入其附带运行的普通套件 |
| Windows Go 实际锁定核心回归 | 164 个通过事件、81 个顶层通过事件 |
| go vet | Linux amd64 / arm64、Windows amd64 通过；arm64 未运行 |
| gofmt、shell 语法 | 通过 |
| 父网络与进程 | 完整接口 / 路由 / 规则一致，无测试 namespace 进程残留 |

GNOME / KDE 的前阶段 244 个通过事件未在本轮重跑。Linux 核心、Windows 核心和 `0.1.0+4` 预览包未变；本轮未改 Flutter、应用 SVG 或生成安装包，也未操作 FlClash、其服务或用户手机。同期独立 [图标实时复核](runtime-audit-20261017.md)重新导出 44 个 Figma SVG，与应用一致；品牌像素及原生应用图标核验通过，完整页面布局未重新验收。

剩余：将客户端接入公开 Manager 的凭据/遥测/恢复状态、权限核心日志传输、真实 systemd / polkit、安装/升级/卸载、真实 Linux 桌面和切网/休眠、ARM64 运行与 race detector，以及其余平台功能和完整 Figma UI/图标核对。当前结果不能表述为五平台已经完整完成。
