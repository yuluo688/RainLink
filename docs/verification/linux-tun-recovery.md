# Linux TUN 资源租约与显式恢复

后续已完成显式托管核心的区间清理替换与协议标记，见 [Linux 托管 TUN 核心续验](linux-managed-tun-core.md)。本页和原始证据保留为 `.1` 核心阶段快照。

日期：2026-10-17。本轮实现独占资源租约、持久恢复记录及按完整身份清理策略规则的底层 API，并用真实 Linux 内核和锁定核心验证。**尚未接入生产权限辅助进程或 TUN watcher，Linux 仍返回 `tun=false`**。证据为 [tun-recovery-evidence.json](linux/tun-recovery-evidence.json) 和 [tun-recovery-tests.json](linux/tun-recovery-tests.json)。上一阶段 [网络观察验收](linux-network.md) 的证据保留为历史快照。

## 实现与调用约束

- `internal/linuxtun` 的生产入口仅供 root 权限辅助进程使用，恢复目录固定为 `/run/rainlink-tun`。复用 `privatefs` 的私有权限、禁止跟随链接、文件锁和原子持久写入。租约持续持有跨进程锁，分配未被路由或规则引用的专用表，以及完整空闲的 11 个优先级；其他规则的 GOTO 目标也视为占用。
- 恢复记录只保存随机 nonce、网络命名空间、守护进程 / 核心的 PID、启动时刻、boot ID 和资源编号，不含节点或凭据。读取限 4 KiB，严格规范 JSON、完整性摘要和字段校验；损坏、重复字段、链接、不安全权限和未知内容均保留记录并失败。
- 先 `Acquire` 持久记录意图，再启动堵在 stdin 的核心，`BindCore` 成功持久化后才允许发送配置。配置未释放的 prepared 记录只退记录，不删除任何网络对象。绑定失败时不得发送配置，调用者须结束仍堵在 stdin 的核心。
- 锁定的双栈 `auto_route` / `strict_route` 配置事前生成 16 条预期规则，覆盖中途启动失败。`Restore` 先确认核心已退出、同名网卡不存在，再逐条核对和删除，最后回读确认。不会删除网卡、清空表或按优先级区间清理；无法确认时保留恢复记录供重试。
- `Recover` 拒绝活守护进程、活核心或不同命名空间；PID 重用通过启动时刻区分，重启后的旧记录只退记录。`Close` 未恢复时返回 `ErrPending` 并保留记录；调用者应保持租约重试，不能把 Close 当成网络清理成功。Close 后原所有者仍活时，其他进程也不能接管其记录。
- `internal/linuxnet` 增加完整规则比较和确认 ACK 的窄删除。未知属性、标记、协议、取反等仍属于身份，仅规范内核默认值、脱离接口和 GOTO 的内核记账标志。删除前先保守计算内核 selector 可能命中的所有规则，存在多个候选就拒绝。
- `internal/linuxprocess` 复用进程身份检查，GNOME / KDE 恢复沿用原 JSON 结构；共享 TUN 地址提取到 `internal/tunconfig`，Windows 编译行为保留。

本轮内核实测发现：删除时显式传入协议编号 `0` 仍代表“不限定协议”。因此相同 selector 的另一条非零协议规则会使清理被拒绝；不能把显式 `FRA_PROTOCOL=0` 当成精确过滤器。非零协议和不同表的区分分别用“先插入另一条规则，再插入本次规则”的场景验证，避免误删第一条却碰巧通过。

## 实际验收

Go 1.25.5 在 Windows 交叉编译 Linux amd64，在 WSL2 Linux 6.6.87.2 / Alpine 3.22.2 内执行。网络 fixture 使用独立 mount / network / PID namespace 和私有 `/run` tmpfs；普通读取及租约单测为 UID 65534，只有隔离核心场景使用 root。系统代理回归另用 UID 1000、隔离 XDG / Secret Service / 会话总线、Qt6 / KConfig6 和 libproxy。没有操作宿主桌面代理或 FlClash。

| 检查 | 结果 |
| --- | --- |
| 网络与恢复定向 | 111 个通过事件，46 个顶层通过事件；包含父 / 子项及重复读取场景，不等于 111 个独立用例 |
| 事前规则模板 | 16 条预期规则逐一与锁定核心实际规则唯一匹配 |
| 核心正常退出 | 运行时 1 张网卡、2 条专用路由、16 条规则；退出后全部消失，重复恢复成功 |
| 核心强杀 | 网卡与接口路由消失，残留 16 条规则；显式恢复后全部清理，独立 iproute2 最终回读两族均为零 |
| 真实租约与退出守护进程 | stdin 绑定前不发配置，活核心拒绝清理，同进程及另一进程均不能抢租约；原守护进程直接退出后由新进程调用 Recover，强杀核心后恢复到逐字段相同的原始网络状态 |
| 后来规则 | 不同表 / 非零协议的先插入规则保留；协议零歧义、相同 selector 的不同 suppress 规则全部保持原样；已改变的规则身份保留 |
| 取消与失败 | 已取消获取 / 绑定、观察中取消、只读写入失败、重试、日志篡改、链接、超限、活所有者、PID 重用、命名空间 / boot 变化及最终回读不一致通过 |
| GNOME / KDE 回归 | 244 个通过事件、108 个顶层通过事件；七个包和单独密钥环锁定测试，包含两桌面真实本机核心传输和异常恢复 |
| Windows 回归 | 164 个通过事件、81 个顶层通过事件；指定锁定核心，八协议真实本机集成通过；3 项改写当前系统代理的 opt-in 测试未开启 |
| 静态检查 | 全宿主 gofmt，Windows amd64 / Linux amd64 / Linux arm64 vet，更新的 Shell 文件语法检查通过 |
| 隔离回收 | 两批父网络空间的全部网卡、双栈所有表路由和规则前后逐字相同，无对应测试命名空间进程残留，私有挂载随退出释放 |

原始状态：[核心强杀与清理](linux/tun-recovery-core-killed.json)、[持有租约恢复](linux/tun-recovery-lease-held-lease.json)、[原守护进程退出后恢复](linux/tun-recovery-lease-dead-guardian.json)。当前宿主能力见 [host-status](linux/tun-recovery-host-status.json)。证据绑定 111 个宿主源码及依赖 / fixture 文件摘要、锁定核心和实际测试产物摘要。

系统代理回归跳过的 Linux 上游用例已在网络 fixture 中执行；Windows 专属上游用例在 Windows 执行；密钥环锁定项在主批次跳过后单独执行通过。无图形环境的系统解锁提示器无法启动是锁定测试的预期条件，不代表完成真实桌面授权验收。未运行 race detector，ARM64 仅静态检查。

首次取消单测误用了前一上下文的 cancel，已修正测试；首次内核删除测试暴露协议零 wildcard，已修正生产 selector；系统代理回归首次完整快照遇到 WSL 启动 IPv6 DAD 新增本地路由。失败记录均保留在 QA 目录。等待启动稳定后重跑，比较仍覆盖全部状态，没有过滤差异或弱化断言。工作区外仅留下空临时挂载目录。

## 尚未完成

这些 API 尚未连接生产提权流程，测试中的 Recover 是显式调用，不是已部署的异常恢复服务。仍需安装可信辅助程序、认证私有 IPC、受控配置编译、核心父进程死亡处理，以及在释放配置前确认 watcher 就绪。

锁定 sing-tun 在启动 / 正常退出时仍会按整个优先级区间删除规则，需要修改并重新锁定核心清理行为。当前“回读后删除”也不是内核原子 CAS，不能保证外部进程在两个系统调用之间替换完全相同 selector 时的所有权。后续必须一并处理，才可开放 Linux TUN；本轮歧义拒绝和后来所有者测试不能替代这两项工作。

实际 TUN TCP / UDP / DNS 转发、系统 DNS 集成、真实 Linux 桌面及 ARM64 执行尚未验收。本轮未修改 Flutter UI、图标或数据库，未复验真实订阅、未生成新安装包，既有 Windows 0.1.0+4 包保留。

Linux amd64 QA 可运行 `sudo bash tools/verify_linux_network.sh`。本次实际运行的是 Windows 交叉编译产物与该入口共用的 namespace fixture；外层完整 Linux Go 构建入口仅完成语法检查。
