# Linux TUN 独立监控与孤儿会话恢复

日期：2026-10-17。新增 root 专用独立 watchdog：监控原权限进程退出，停止其绑定的核心并精确恢复规则。已通过实际 Linux 命名空间测试，**尚未接入生产提权、认证 IPC 或首页开关，Linux 仍返回 `tun=false`**。证据为 [watchdog-evidence.json](linux/watchdog-evidence.json) 和 [watchdog-tests.json](linux/watchdog-tests.json)；[托管核心验收](linux-managed-tun-core.md)保留为前一阶段快照。

## 实现与接入要求

`internal/linuxprocess.Handle` 在打开 pidfd 前后核对 PID、启动时刻和 boot ID。等待及终止都使用该内核句柄，不回退到按 PID 发信号；PID 重用、错误 boot、无效记录均不能授权终止新进程。等待可取消，句柄可重复关闭。后台监控直接阻塞在内核通知上，不周期轮询；有取消上下文的短操作以最多约 100 ms 的间隔响应取消，不创建等待 goroutine。

`Controller.WatchOwner` 只接受同一网络命名空间、身份匹配的 root 父进程。打开进程监控后，通过继承的管道返回就绪字节，随后等待父进程退出。内部 `rainlink-host watch-tun` 入口不提供提权，参数只有进程身份；管道先设为 nonblocking 再注册 Go poller，使就绪写入的 2 秒期限实际有效。该入口供可信权限进程使用，不是普通 GUI 的连接接口。

`RecoverOrphan` 在持有资源租约锁时核对预期所有者与持久记录。活所有者、记录属于新会话、不同命名空间或无法确认身份时拒绝处理。确认原权限进程死亡后，只向记录绑定的核心 pidfd 发送 SIGTERM，约 500 ms 后仍未退出则发送 SIGKILL，停止期限最多 4 秒；确认退出后才复用完整身份规则恢复。总体恢复上限 20 秒，失败保留日志供重试。原 `Recover` 继续拒绝活核心，不具备此终止能力。

后续权限辅助进程必须按以下顺序接入：

1. 启动独立 watchdog，等到就绪，并持续监控其退出。
2. 获取租约并持久记录资源意图。
3. 启动仍堵在 stdin 的受信核心，持久 `BindCore`。
4. 释放配置、关闭 stdin，核验实际核心和 TUN 状态后才确认连接。
5. 正常断开先停核心、恢复并关闭租约；watchdog 丢失时停止本次连接，不能继续无监控接管。

本轮实际执行了上述启动顺序的隔离 fixture；生产辅助进程、安装与第 5 项的在线故障联动尚未接入。

## 真实内核验收

Windows Go 1.25.5 交叉编译，WSL2 Linux 6.6.87.2 / Alpine 3.22.2 中执行。使用独立 mount、network、PID namespace 和私有 `/run`；普通单测为 UID 65534，只有隔离 TUN 场景使用 root。自动恢复测试调用实际编译的 `rainlink-host watch-tun`，不使用测试代码模拟恢复回执。FlClash 及宿主桌面系统代理未被操作。

| 场景 | 实测行为 |
| --- | --- |
| 核心存活，权限进程被强杀 | 核心没有设置 Pdeathsig；独立 watchdog 在原权限进程死亡后停止核心，清理 16 条托管规则并退掉恢复记录 |
| 核心先被强杀 | 先留下 16 条规则，再强杀权限进程；watchdog 自动完成恢复 |
| 只获取租约 | 未启动或绑定核心；强杀权限进程后只退记录，不删除其他网络对象 |
| 核心忽略 SIGTERM | fixture 先确认忽略信号，再绑定进程；watchdog 用 pidfd 升级到 SIGKILL，确认退出并完成恢复，此场景未创建 TUN 转发 |
| 所有权和取消 | 活所有者、新所有者、不同命名空间、取消保留记录与活进程；模拟 starttime 不符时不终止该 PID 的新所有者，旧规则按身份恢复 |
| 进程监控 | 实际子进程等待、取消、退出与信号验证通过；关闭 / 零值句柄不能发信号，拒绝非终止信号 |

最终四种自动恢复场景各连续运行 5 次，共 **20 次**，全部通过；另一次较早的五轮运行也通过。自动恢复路径没有在强杀权限进程后由父测试调用 Recover 来补清理。每次核对核心确已退出、恢复记录已删除、完整网络状态与初始值逐字段相同。原始快照为最终轮次：[核心存活](linux/watchdog-watchdog-core-live.json)、[核心先退出](linux/watchdog-watchdog-core-dead.json)、[只获取租约](linux/watchdog-watchdog-prepared.json)、[忽略 SIGTERM](linux/watchdog-watchdog-term-resistant.json)；日志包含全部 20 次。

| 回归检查 | 结果 |
| --- | --- |
| 网络及恢复 | 152 个通过事件、58 个顶层通过事件；包含父 / 子项及五轮重复，不等于 152 个独立用例 |
| GNOME / KDE | 244 个通过事件、108 个顶层通过事件；新宿主、七个包、实际密钥环与 Qt6 / KConfig6 / libproxy 后端回归 |
| Windows Go | 164 个通过事件、81 个顶层通过事件，八协议本机集成通过；3 项改写当前系统代理的 opt-in 未开启 |
| 静态检查 | gofmt、Windows amd64 / Linux amd64 / arm64 vet、Python / Shell 语法通过 |
| 隔离回收 | 两批父网络空间的全部网卡、双栈全表路由和规则前后逐字相同，无 fixture 命名空间进程残留 |
| 核心 | Linux `.2` 与 Windows `.1` 二进制均未变化；源码包独立复现结果沿用前阶段相同产物 |

证据绑定 125 个源码 / 构建文件、实际宿主与测试二进制摘要。未重跑 Flutter 或视觉测试，因为本轮未修改界面与图标；未生成新预览包。

## 失败记录与剩余边界

首次就绪管道不支持 deadline，已修正继承 FD 初始化；一次 fixture 在关闭 stdin 前等规则，已按核心实际 EOF 语义修正顺序，未放宽启动期限。失败日志保留。

一次增加完整诊断前的 SIGTERM 忽略场景中，watchdog 退出后仍留下恢复记录，当时未捕获具体错误。后续阶段以 80 次压力复现其中 4 次：读取 `/proc/PID/stat` 返回 ESRCH，原判断只识别 ENOENT。已精确修复并保留错误分类回归，随后同样 80 次全部通过；完整日志与当前源码验收见 [权限通信续验](linux-tun-permission.md)。本文及下方边界保留为原阶段快照，不把旧摘要用于证明新增源码。

生产权限流程、可信安装、认证 IPC、辅助进程持续监控 watchdog、服务重启恢复及实际 TUN TCP / UDP / DNS 尚未完成。系统 DNS、真实桌面授权、ARM64 运行和 race detector 尚未验收；同协议 242 / 同 selector 的并发外部替换仍不具备内核 CAS 保证。以上边界未通过前保持 Linux TUN 关闭，全页面 Figma / 图标核验也仍在后续范围。
