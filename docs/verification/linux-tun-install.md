# Linux 权限服务安装与恢复验收

日期：2026-10-17。本轮新增固定路径安装、升级、卸载及持久回滚。它不修改 Flutter 布局、用户数据库、订阅或密钥环，不开放公开 Linux TUN 能力。

## 实现

管理员运行发行包中的 `rainlink-host install-tun`。只复制正在运行的宿主、相邻且符合该宿主摘要锁的核心，以及编译嵌入的两份 systemd 单元和一份 polkit 策略。不接受安装目录、执行路径或命令参数；资产与 `packaging/linux` 保持单一来源。

`rootfs` 逐级打开 root:root、不可由组或其他用户写入的目录，拒绝符号链接。文件必须为单链接普通文件，不接受额外特权位。复制先进入 root 私有暂存区，校验摘要后以临时 inode、文件 fsync、原子 rename、目录 fsync 安装。管理员修改、未知旧文件、掩码或 systemd 覆盖项会阻止替换。

`/var/lib/rainlink/tun-install` 的私有锁、清单、事务日志和备份支持重入恢复。替换前停止 socket 与全部 RainLink 实例，严格恢复并确认 TUN 空闲，再禁用 socket。失败使用独立的有界上下文恢复原文件和原服务状态。文件、清单与实际服务回读确认后提交；提交后仅完成清理。升级保留 socket 的启用/运行状态。恢复失败保留事务，下一次管理操作先恢复。

卸载只删除清单管理的五个文件，不递归删除未知文件、目录、用户配置或凭据。`recover-tun-install` 显式恢复未完成事务。物理断电、发行版包管理整合、GUI 权限提升与正式分发仍待验收。

## 退出清理修正

systemd 为只读探测创建单独实例，其退出也触发 `ExecStopPost`。原严格恢复在另一个会话持有租约时会返回错误，使正常探测实例被标记失败。新增专用 `recover-tun-service`：明确记录另一个会话仍活动并跳过清理，保留该会话与 journal；损坏状态仍返回错误。安装和用户断开继续严格调用 `Recover` / `ConfirmIdle`，跳过不等于网络已恢复。

## 隔离验证

私有 mount/PID/network namespace 验证文件和事务；真实 CLI 另运行在独立 Alpine rootfs。此阶段 systemctl、socket activation 和 pkcheck 是显式 fixture，不算真实 systemd 或授权弹窗验收。

- 安装、升级、卸载各十个阶段的真实 SIGKILL，共三十次；恢复原版本或保留已提交版本。同样三十个阶段的普通错误也通过。
- 停止、重载、启用、启动、就绪失败和取消后回滚；未确认网络恢复时不替换文件。
- 缺失备份、外部修改、坏清单保留恢复记录；链接、FIFO、可写祖先、外来所有者及 setuid 文件拒绝。
- 实际安装命令复制完整锁定核心，通过真实 Unix 私有协议确认空闲，重复升级并保留禁用状态，拒绝损坏核心与普通用户安装，卸载保留未知文件。

入口：`tools/verify_linux_install.sh`。当前 QA 在 `build/qa/linux-install`，数据均为合成数据。上轮 `linux-manager` 证据保持原样，网络回归使用独立的 `linux-install-network`。

## 真正 systemd 验收

独立 QEMU 的 Debian 13、Linux 6.12.113、systemd 257 真实验收通过（141.49 秒），基础镜像核对官方 SHA512。实际安装、socket activation、继承 socket 的 root 身份检查、idle 私有协议、退出钩子、重复升级、保留禁用状态、管理员覆盖项拒绝、普通用户拒绝及卸载通过。活动资源租约（未创建 TUN 或启动核心）阻止替换并保留事务，释放后显式恢复原服务通过；退出时无活动权限实例。此轮没有请求 polkit 授权，不证明活动桌面用户的认证弹窗。

真实日志与源码摘要见 [安装证据](linux/install-evidence.json)、[systemd 完整测试](linux/install-real-systemd-tests.log)及[系统 journal](linux/install-systemd-journal.log)。真实服务与模拟服务分别计数。通用 Linux QA 入口 `tools/verify_linux_systemd_vm.sh` 已做语法检查；本机实际使用相同 QEMU/云初始化流程的私有 Alpine 引导器，脚本及软件包摘要一并保留。

历史尝试保留：TCG 初次引导停在 SMM，关闭该虚拟固件功能后进入真实系统；第一轮查询发现 systemd 不能直接查询未实例化的 `@.service` 模板，已改为只读加载固定非运行实例。日志提取曾等待覆盖已有文件确认，后改为每轮独立结果目录。这些尝试不计作功能通过。

## 回归边界

Windows 全量 Go 回归 164 个通过事件，三项需显式改变系统代理的测试跳过。首轮 Shadowsocks fixture 只检查 TCP，选中 Windows 禁止的 UDP 区间；现在真实检查两种端口，全量重跑通过，原失败日志保留。Linux 网络、核心、通信、租约、watchdog 与十四个宿主场景整套重跑通过：父 namespace 的链路、双栈路由及规则保持，原安装文件保持，无测试进程残留。

此前 Flutter 440 项属于前阶段，本轮无 Dart 修改，未将旧结果当作新运行。macOS/iOS、完整 Linux 桌面、真实活动用户 polkit 提示、权限核心日志传输、分发及完整 UI 对照仍待推进。
