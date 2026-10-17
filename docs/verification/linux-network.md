# Linux 网络观察与 TUN 前置验收

日期：2026-10-17。本轮完成网络状态读取和 TUN 准备流程，**尚未开放 Linux TUN**。当前宿主实际返回 `connect=true`、`tun=false`；启用 TUN 的请求仍在启动核心前拒绝。证据见 [network-evidence.json](linux/network-evidence.json) 和 [network-tests.json](linux/network-tests.json)。

后续已完成[资源租约恢复](linux-tun-recovery.md)、[托管核心](linux-managed-tun-core.md)与[独立 watchdog](linux-tun-watchdog.md)阶段验收。本页的数量、源码摘要和下一阶段说明保留为前置阶段快照；当前状态以最新续验及实现清单为准。

## 改动

- 新增 `internal/linuxnet`，直接读取 rtnetlink 网卡、IPv4 / IPv6 路由及策略规则，不依赖解析 `ip` 文本，不修改网络。支持大于 255 的路由表、多路径、规则匹配属性及未知属性的原始字节。
- 每次完整读取限 2 秒；支持取消，轮询最多 25 ms 后重新检查上下文。单个数据报限 64 KiB，单次 dump 限 8 MiB / 16,384 条消息。来源、序列号、端口、长度、截断、内核错误及中断均检查；失败丢弃本次结果，不返回部分成功。
- 上游按 IP 家族选择主表中的普通默认路由，排除隧道、回环、失效接口、源地址限定路由及失效下一跳；保留 bridge / bond / VLAN / veth 等实际出口。按 metric、IPv6 路由器优先级和接口索引选择，选择后重新检查接口身份。尚不推测 VRF / 仅策略表路由或未解析的 nexthop object；这些环境明确失败。
- TUN 准备流程传递取消上下文，Linux 名称改为 `rl-` 加八位随机值，符合 15 字节上限；Windows 名称格式保留。新 Linux 上游实现已经由准备流程实际调用，但没有绕过现有 TUN 能力限制。
- 同步修正宿主协议文档中已过时的 KDE 未实现描述。

## 实际运行

Windows Go 1.25.5 交叉编译 Linux amd64 测试与宿主，在 WSL2 Linux 6.6.87.2 中执行。经 SHA-256 校验的 Alpine 3.22.2、九个签名验证通过的 APK，iproute2 6.15.0、setpriv 2.41.6。使用私有 mount / network / PID namespace 和 tmpfs，普通观察与准备测试为 UID 65534；仅锁定核心的规则生命周期用例在该隔离空间内使用 root。

| 检查 | 结果 |
| --- | --- |
| Linux 定向测试 | 56 个通过事件、29 个顶层通过事件，包含附着 / 删除网卡两次运行及父 / 子用例；不是 Linux 全量回归 |
| 普通用户读取 | 真实网卡、双栈路由、策略规则、扩展表 100001、IPv4 / IPv6 不同上游均通过 |
| 接口移除 | 网卡及接口路由消失，但两族策略规则仍存在，读取结果正确保留残留 |
| TUN 准备与编译 | Linux 短名称、实际上游、提前取消、隔离测速禁止接管，以及真实核心配置 check 通过 |
| 锁定核心正常退出 | 运行时 1 张网卡、2 条专用表路由、16 条规则；SIGTERM 后三项均为零 |
| 锁定核心强杀 | SIGKILL 后网卡及路由为零，16 条规则仍存在；独立 iproute2 分别确认 IPv4 / IPv6 各 8 条，优先级与表编号相符 |
| Windows Go 回归 | 164 个通过事件、81 个顶层用例；3 项修改真实系统代理的 opt-in 用例未开启 |
| 静态检查 | 全宿主 gofmt、Windows amd64 / Linux amd64 / arm64 vet，以及两个新增 Shell 文件语法检查通过 |
| 隔离清理 | 父命名空间网卡、双栈所有表路由与规则的前后文本逐字相同；无该测试命名空间进程残留，私有挂载随退出释放 |

锁定核心在本轮测试中使用空 `PATH`，避免其通过 `resolvectl` 接触宿主 DNS 管理器。测试前确认专用表和完整优先级范围未占用，关闭 `auto_redirect`。这些是隔离 QA 约束；本轮没有证明生产权限流程、系统 DNS 集成或 TUN 的真实 TCP / UDP / DNS 传输。

原始内核观察见 [正常退出](linux/network-core-graceful.json)、[强杀退出](linux/network-core-killed.json)、[附着网卡](linux/network-kernel-attached.json)、[删除网卡](linux/network-kernel-removed.json)。独立命令读回见 [IPv4 规则](linux/network-ip-rules4-core-killed.json) 和 [IPv6 规则](linux/network-ip-rules6-core-killed.json)；新编译宿主的状态为 [host-status](linux/network-host-status.json)。

首次前后快照检查遇到 WSL 刚启动时的 IPv6 link-local DAD：父空间自行新增了一条本地 IPv6 路由，因此该次完整检查失败。保留了失败记录，等待初始化稳定后重新运行，仍逐字比较全部网卡 / 路由 / 规则，最终通过；没有过滤差异或放宽断言。外层临时挂载点为空目录，未尝试删除工作区外的旧目录。

## 复验与下一阶段

Linux amd64 QA 主机可运行 `sudo bash tools/verify_linux_network.sh`，需要 Go / Python、iproute2、setpriv、unshare、mount 和 `/dev/net/tun`。入口在临时命名空间中运行普通用户观察及锁定核心测试。本次实际执行的是 Windows 交叉编译产物和该入口共用的 fixture；外层 Go 构建脚本完成语法检查，未在完整 Linux 开发环境执行。ARM64 仅完成静态检查。

下一阶段需实现独立权限辅助进程、专用资源的冲突检查与独占租约、持久恢复记录、守护进程异常清理，以及后来所有者的保留。锁定核心自身的启动 / 退出会按整个优先级区间删除规则；仅启动一个提权进程或仅结束核心不足以保证这些恢复语义。读取网卡消失也不能证明规则已经清理。

本轮未修改 Flutter 界面、图标或数据库，未操作 FlClash / 其服务和用户手机，未重新测试真实订阅或远端节点，未生成新安装包。先前 KDE / GNOME、Flutter 和真实外网验收仍分别保留原来的范围；全页面 Figma 验收继续列为后续工作。
