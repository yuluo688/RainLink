# Linux 托管 TUN 核心与精确恢复

后续已加入 root 专用独立监控及自动孤儿恢复，见 [TUN watchdog 续验](linux-tun-watchdog.md)。本页和对应机器证据保留为托管核心阶段快照。

日期：2026-10-17。Linux 核心增加显式托管模式，替换该模式下上游按优先级区间删规则的行为；恢复记录升级为 version 2。**生产权限辅助进程与 TUN watcher 尚未接入，Linux 仍返回 `tun=false`**。机器证据为 [managed-tun-evidence.json](linux/managed-tun-evidence.json) 和 [managed-tun-tests.json](linux/managed-tun-tests.json)。[上一阶段](linux-tun-recovery.md)保留为历史快照。

## 实现边界

Linux 桌面核心版本为 `1.12.25-rainlink.2`，Windows / Android 保留原 TLS 扩展变体 `1.12.25-rainlink.1`。两套源码目录与 overlay 相互独立。只有 Linux TUN 入站显式设置 `rainlink_managed=true` 时采用新路径；未设置该选项继续保留上游行为，不能单独使用原行为代替托管会话。

托管模式限定固定双栈地址、MTU 1500、`auto_route` / `strict_route` 和租约分配的短网卡名、表与优先级；拒绝不可控的额外路由、UID、重定向等选项。启动前和添加规则前检查两族路由、完整优先级区间与 GOTO 目标，使用 `IFF_TUN_EXCL` 创建独占网卡。16 条规则均带非零协议编号 **242**，独立 netlink handle 的 socket 期限为 2 秒。

托管路径不执行上游 `unsetRules()` 区间删除，不按网卡名字删除路由或地址，不调用 `resolvectl`。正常 Close 仅关闭自己持有的独占 TUN FD；网卡及接口路由随 FD 消失，正常退出与强杀均留下规则供 guardian 精确恢复。动态路由更新明确要求重连。启动过程中发生冲突也由事前记录的规则模板恢复；必须先持久 `BindCore`，再向 stdin 释放配置。

`internal/linuxtun` 新记录使用 version 2 / 协议 242，兼容读取 version 1 / 协议零的旧记录。旧版删除仍受内核协议零 wildcard 保护：存在多个潜在匹配时拒绝清理，不能以新标记误认旧记录。非零标记提供更窄的内核过滤条件，仍需完整身份比较、独占租约及核心先退出的约束。

## 实际验证

Go 1.25.5 在 Windows 交叉编译，在 WSL2 / Alpine 3.22.2 的独立 mount、network、PID namespace 内执行。普通网络与核心扩展单测为 UID 65534；root 仅用于隔离 TUN 场景，`/run` 为私有 tmpfs。GNOME / KDE 回归使用 UID 1000、隔离 XDG、会话总线、密钥环与实际 Qt6 / KConfig6 / libproxy。未操作本机 FlClash 或宿主桌面系统代理。

| 检查 | 实测结果 |
| --- | --- |
| 网络与资源恢复 | 120 个通过事件、51 个顶层通过事件，含父 / 子项和重复场景 |
| 托管核心扩展 | 3 项单测在实际 Linux 普通用户进程执行，覆盖受控配置、禁止区间清理 / 原位更新、双栈及 GOTO 冲突 |
| 正常退出 / 强杀 | 运行时 1 张网卡、2 条接口路由、16 条协议 242 规则；退出后网卡 / 接口路由消失、16 条规则留下；恢复后全部清理 |
| 启动前冲突 | 获取租约后插入冲突规则或 IPv6 路由，核心失败且对象逐字段不变；同名 dummy 网卡保留并使恢复返回 pending，fixture 自行删除它后才能完成恢复 |
| 后来所有者 | 核心就绪后插入同优先级 / 同表的双栈协议 99 规则及独立 blackhole 路由；正常退出保留它们，恢复只清本次 242 规则，另一个所有者的 2 条规则与 1 条路由仍在 |
| 系统 DNS 调用 | 冲突及后来所有者场景的 PATH 仅含写 marker 的假 `resolvectl`，启动 / 关闭均未调用；基础及租约生命周期场景使用空 PATH |
| 租约与恢复 | 活核心拒绝清理、跨进程竞争、死 guardian 恢复、version 1 兼容以及取消 / 损坏 / 歧义保护通过 |
| GNOME / KDE 回归 | 244 个通过事件、108 个顶层通过事件；包括实际本机核心传输、跨桌面恢复与锁定密钥环 |
| Windows 回归 | 164 个通过事件、81 个顶层通过事件；八协议本机核心集成，3 项修改当前系统代理的 opt-in 测试未开启 |
| 静态检查 | 宿主与扩展 gofmt；宿主 Windows amd64 / Linux amd64 / arm64 vet；Linux 核心修改包及两个依赖 vet；Python 和 Shell 语法通过 |
| 隔离回收 | 两批父网络空间的网卡、双栈全表路由及规则前后逐字相同；无 fixture 命名空间进程残留 |

原始快照：[核心退出](linux/managed-tun-core-graceful.json)、[强杀](linux/managed-tun-core-killed.json)、[启动规则冲突](linux/managed-tun-managed-startup-policy-collision.json)、[IPv6 路由冲突](linux/managed-tun-managed-startup-route-collision-v6.json)、[同名网卡](linux/managed-tun-managed-existing-interface.json)、[后来所有者](linux/managed-tun-managed-graceful-later-owner.json)。证据绑定 119 个源码 / 构建文件、实际 QA 二进制和日志摘要。

## 构建与失败记录

Linux 核心 SHA-256 为 `640e5293d90b94c71318031284e65cf8121d99ee9c06482f021ed77c9f3fa96d`。Windows 重新构建仍为 `cf6863552456c535fd79a0724f2d01352e77c97f4958466b75d9f07d8f0edef7`，与此前完全相同。Linux 源码包包含 1131 个文件、相对路径替换的 sing-tun / netlink 源码及许可证；解压后无需 overlay 或补丁脚本即可重建出相同 Linux 二进制。

核心静态检查最初发现 pinned netlink 的嵌入结构体使用位置字段，已在独立源码副本中改为具名字段，校验原始文件摘要，未修改模块缓存或关闭检查。该机械修改未改变 Linux 核心及扩展测试二进制，故已有实际运行结果继续对应当前产物；新源码包已重新独立构建并通过 vet。

Windows 首轮全量中一项 SS AEAD fixture 未在原 3 秒期限内监听，首次日志不足以确认原因。已增加脱敏启动诊断；同一单项与随后全量通过，未在测试内重试或放宽期限，失败日志保留。核心最初静态失败同样保留在 QA 目录。

## 剩余工作

生产 Linux 提权、可信安装、认证私有 IPC、父进程死亡处理和 watcher 就绪握手尚未连接，不能开放 TUN 开关。回读与删除不是内核 CAS；不能保证另一个 root 在两个系统调用间以同协议 242 和相同 selector 替换资源时的所有权。

实际 TUN TCP / UDP / DNS 转发、系统 DNS 集成、真实桌面授权、ARM64 执行尚未验收；未运行 race detector。`sudo bash tools/verify_linux_network.sh` 是 Linux amd64 正式入口，本轮实际执行的是 Windows 交叉编译产物和该入口共用的 namespace fixture，外层构建入口仅检查语法。本轮未修改 Flutter UI、图标或数据库，未复验真实订阅，也未重新打包 Windows / Android 预览。
