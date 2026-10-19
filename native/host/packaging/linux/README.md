# Linux 权限服务与安装管理

2026-10-20 新增 Linux 设置页管理入口及独立 `manage-tun-service` 协议，支持状态、安装/更新、卸载、恢复和取消。当前已通过单元测试、Flutter 回归和静态检查；真实 `pkexec` 管理 VM 因依赖下载失败未进入测试，桌面认证及 Linux GUI 仍待验收，公开 TUN 保持关闭，见[服务管理阶段记录](../../../../docs/verification/linux-tun-service-management.md)。下文“GUI 入口未完成”等描述属于前阶段验收范围。

已新增管理员命令安装、升级、卸载和持久恢复，当前普通宿主继续报告 `tun=false`。安装事务与真实 CLI 的隔离测试使用 fixture 服务驱动；真实系统结果另行标注，见[安装验收](../../../../docs/verification/linux-tun-install.md)。内核身份固定使用 `SO_PEERPIDFD`，要求 Linux 6.5 及以上。

固定安装位置：

| 输入 | 固定位置 | 所有者 / 权限 |
| --- | --- | --- |
| 当前平台 `rainlink-host` | `/usr/libexec/rainlink/rainlink-host` | root:root / 0755 |
| 摘要锁定的 `sing-box` | `/usr/libexec/rainlink/sing-box` | root:root / 0755 |
| `rainlink-tun.socket` | `/usr/lib/systemd/system/rainlink-tun.socket` | root:root / 0644 |
| `rainlink-tun@.service` | `/usr/lib/systemd/system/rainlink-tun@.service` | root:root / 0644 |
| `org.rainlink.tun.policy` | `/usr/share/polkit-1/actions/org.rainlink.tun.policy` | root:root / 0644 |

所有可执行文件的祖先目录必须由 root 控制，不可由组或其他用户写入，不接受符号链接。服务校验打开的核心 inode 并通过同一继承 FD 执行，不从请求中接收执行路径。安装器先停止 socket 和全部实例、确认网络恢复，再替换已验证的文件；失败保留事务并恢复原文件和服务状态。未知文件、管理员修改、systemd 覆盖项和损坏备份不会自动覆盖。

管理员在发行包的宿主与锁定核心相邻时运行：

```sh
sudo ./rainlink-host install-tun
sudo /usr/libexec/rainlink/rainlink-host recover-tun-install
sudo /usr/libexec/rainlink/rainlink-host uninstall-tun
```

首次安装启用并启动 socket，升级保留原启用及运行状态。事务在 `/var/lib/rainlink/tun-install`。卸载只删除清单管理的五个文件，保留未知文件与用户数据；失败后修正故障，使用发行包内的恢复命令重试。GUI 入口和发行版包管理整合仍未完成。

socket 每个连接启动一个 root guardian。guardian 先以 socket 创建方的 PID、启动时刻和 UID 请求固定权限项，再等待独立 watchdog 就绪、获取独占资源租约、编译和校验配置、持久绑定子进程，最后通过 stdin 传入配置。正常停止或 EOF 均先停止核心再精确恢复。watchdog 丢失时 guardian 停止本次连接；guardian 被强杀时 watchdog 恢复。`ExecStopPost` 使用专用的 `recover-tun-service`：另一个租约仍活动时明确跳过，不误报该会话已恢复。该退出钩子已在真正 systemd 中验证只读实例与活动租约；真实核心运行时的 systemd 整组进程清理仍待续验。

策略只向活动本地会话请求管理员认证；不接受远程或非活动会话，不缓存授权。pkcheck 的 action、程序位置和环境固定，超时或调用方变化会取消。普通 Manager 已接入真实 Secret Service、节点/链/规则、遥测、日志和确认断开，15 个完整宿主场景通过。生产客户端用无 payload 的 `hello-logs` 显式启用私有脱敏日志；旧 `hello` 不接收异步日志，`idle` 只观察锁与 journal，不恢复也不请求授权。每连接日志缓冲有上限，核心输出不等待 IPC；停止先恢复，再排出有界末尾日志并确认停止。真实 systemd 安装、升级、卸载和恢复已在独立 Debian VM 验收，最新实际 polkit YES / NO 路径及核心日志见[日志验收](../../../../docs/verification/linux-tun-logs.md)。VM 使用临时 UID / action 规则，活动桌面密码弹窗、GUI 管理和分发仍待完成，公开能力继续关闭。fixture 复验使用私有 `/usr` 挂载，不修改原系统授权器。
