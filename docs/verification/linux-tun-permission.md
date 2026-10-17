# Linux TUN 权限通信与 guardian 验收

后续进展见 [实际转发与原生客户端](linux-tun-forwarding.md)：已完成隔离双栈 TCP/UDP/DNS 及普通 UID 私有客户端验证。本文以下保留权限阶段当时的测试范围和源码/产物快照。

2026-10-17：已实现并隔离验证内核身份认证、受控协议、固定 polkit 调用与独立 root 会话生命周期。七种 guardian 场景各运行三轮，共 **21 次**通过；当前 watchdog 四种场景各五轮，共 **20 次**通过。**真实桌面的 polkit、systemd 启动、普通宿主接入及 TUN 数据转发仍待验收，公开能力继续为 `tun=false`。**

本阶段证据：[permission-evidence.json](linux/permission-evidence.json)、[测试目录](linux/permission-tests.json)、[隔离运行日志](linux/permission-namespace-run.log)。前一阶段的 [watchdog](linux-tun-watchdog.md) 与 [托管核心](linux-managed-tun-core.md) 文档及哈希为历史快照。

## 权限边界

- Unix stream 的 UID、PID 来自内核 `SO_PEERCRED`；用 `SO_PEERPIDFD` 固定真正的 socket 创建方，避免其死亡、进程号复用后误认新进程。该路径要求 Linux **6.5+**，旧内核的安全替代路径尚未实现。
- 每次授权前后核对启动时刻、boot ID、四个 UID 槽和进程存活；服务核对调用方与自己位于同一网络命名空间。普通用户无法读取 root 的 namespace 链接，因此客户端使用单独的 root 服务认证入口；服务端仍严格检查调用方 namespace。客户端还必须连接安装在 root 控制目录内的固定 socket。
- polkit action 固定为 `org.rainlink.tun.manage`，subject 为真实 socket 创建方的 `PID,start-time,UID`。固定执行 `/usr/bin/pkcheck`，清理继承环境，最多 60 秒；成功后重新检查对端。没有从消息接收授权主体、action、可执行路径或 root 身份声明。
- 程序和全部祖先目录必须由 root 控制，不可被组或其他用户写入，拒绝 symlink。核心打开后按锁定摘要校验，通过同一个继承 FD 执行；配置与凭据只经 stdin，不写 argv、临时配置或系统日志。

本轮用真实 socket、普通 UID 65534、root→65534 实际降权进程验证身份和撤销。授权测试调用安装于临时 rootfs 的 **fixture pkcheck**，验证固定参数、允许/拒绝/关闭/不可用、超时终止、环境隔离及授权后 UID 再检查。它没有执行真实系统授权对话框。安装策略与 systemd 文件是待系统验收的输入，见 [安装说明](../../native/host/packaging/linux/README.md)。

## 私有协议与受控编译

帧使用四字节大端长度，最大 128 KiB；读写分别串行，排队可取消。空闲等待不设置周期超时；收到首字节后，剩余头部和正文共用十秒上限。拒绝无效 UTF-8、重复解码键、过深 JSON、尾随数据和异常长度，错误不包含原始输入。取消等待后的 deadline 不污染下一次操作；调用方 deadline 与 I/O timer 竞争时仍返回正确的超时类别。

协议版本为 1，入口仅允许：

| 方法 | 参数 | 时机 |
| --- | --- | --- |
| `start` | `MobileRequest` 同域的节点/代理链、规则、网络设置及内存凭据 | 每个连接恰好一次 |
| `stop` | 无 payload | 收到启动成功后，id 大于 start 的 id |

连接建立期间取消使用关闭 socket；进程退出或 EOF 也取消授权与启动。失败回执只给固定错误码。成功回执中的 API 端口和密钥仅供原生宿主，只有公开 Snapshot 可发往 Flutter；完整日志和普通宿主接入尚未实现。

`CompileLinuxTUN` 不接受完整 sing-box JSON、二进制路径、接口名或路由表覆盖。资源只来自 root 持有的租约；复用现有协议、代理链、规则和高级配置校验，添加双栈托管 TUN、上游网卡绑定和 DNS 截获。拒绝低于 1024 的本地监听端口，编译结果保持 `connecting`；只有实际 API、TUN、两族路由及全部 16 条托管规则均确认后才报告 `connected`。编译及核心 check 前后完整网络状态一致。

## 生命周期

每个 root guardian 只服务一个连接：授权通过 → 校验安装程序 → 等 watchdog 就绪 → 持久获取资源 → 编译与 check → 启动尚未获得配置的核心 → 持久绑定核心身份 → 写入 stdin → 确认 API 与网络资源。watchdog 在初始化及连接期间均受监控；停止时先停监控，再终止核心、确认退出、恢复租约，成功后退出 watchdog。清理失败保留 journal 和独立 watchdog，不返回停止成功。

| 场景 | 实际验证 |
| --- | --- |
| 正常 stop | 核心退出、16 条规则恢复、journal 删除后才收到停止确认 |
| socket EOF | 取消会话并完整恢复 |
| 客户端被强杀 | 原生服务结束本次接管，无孤儿核心 |
| 核心被强杀 | guardian 检测退出并恢复 |
| watchdog 被强杀 | guardian 停止核心并恢复，连接不会继续失去保护 |
| guardian 被强杀 | 独立 watchdog 停止绑定核心并恢复；没有由父测试补调 Recover |
| 系统授权拒绝 | 不启动接管，不产生租约与恢复残留 |

原始日志含全部 **21 次**，每场景最后一轮的 [正常停止](linux/permission-stop-state.json)、[EOF](linux/permission-eof-state.json)、[客户端退出](linux/permission-client-killed-state.json)、[核心退出](linux/permission-core-killed-state.json)、[watchdog 退出](linux/permission-watchdog-killed-state.json)、[guardian 退出](linux/permission-guardian-killed-state.json)、[拒绝](linux/permission-permission-denied-state.json)保存完整前/就绪/后快照。六种已连接场景均有一张 TUN、两条专用路由和 16 条规则；恢复后与前值逐字段相同，进程确已退出且 journal 已删除。

## 发现并修复的问题

1. 早期 watchdog 记录残留已复现：80 次场景中有 4 次读取 `/proc/PID/stat` 返回 **ESRCH**，此前只把 ENOENT 视为进程退出。现只对目标 stat 的这两类结果返回“不存活”；权限、损坏、boot ID 读取错误继续阻止恢复。原始 [失败压力日志](linux/permission-history-esrch-before.log) 与 [修复后 80/80 日志](linux/permission-history-esrch-after.log)保留；它们是历史运行记录，当前新增源码另由本次测试覆盖。
2. `rand.Text` 生成的大写接口名不符合 Linux 租约要求，现统一为小写；生成名称实际交给租约规则验证，有回归断言。
3. socket deadline 可先于 context timer 发布结果，现保留调用方正确的 `DeadlineExceeded` 分类，没有放宽测试。
4. 第一次生命周期比较发现新增四条 IPv6 link-local 本地路由，已确认来自 fixture 的异步 DAD，见 [原始差异](linux/permission-fixture-dad-difference.json)。fixture 现在等待实际 DAD 完成，并给持续 TUN 附加真实队列 FD，避免依赖短暂 UNKNOWN 状态。保留完整网络比较，没有过滤差异或弱化 readiness 断言。

## 检查与边界

| 检查 | 当前结果 |
| --- | --- |
| Linux 网络 / 恢复 / IPC / guardian 定向 | 229 个通过事件，78 个顶层通过事件；含重复压力场景 |
| GNOME / KDE、密钥环、共享会话回归 | 244 个通过事件，108 个顶层通过事件 |
| Windows Go 回归 | 164 个通过事件，81 个顶层通过事件 |
| go vet | Linux amd64 / arm64、Windows amd64 通过 |
| gofmt、shell、安装输入语法 | 通过；安装输入未做实际 systemd/polkit 验收 |
| 隔离父网络、进程清理 | 两个 runner 的完整链接、路由、规则一致，没有残留 namespace 进程 |

Linux 核心仍为 `.2`，Windows 核心和 `0.1.0+4` 预览包未改。未改 Flutter 页面或 SVG，没有将测试代理、流量或 IP 显示成真实服务商结果。FlClash 保持关闭，没有操作其服务、用户手机或既有用户数据库。

剩余：真实 polkit / systemd、服务停止后的 ExecStopPost 恢复、普通宿主凭据与会话接入、TUN TCP/UDP/DNS 实际传输、权限服务日志、安装/升级/卸载、ARM64 运行与 race detector、真实桌面环境以及完整 Figma UI/图标核对。**不能据此称五平台软件已完整完成或 Linux TUN 已对用户开放。**
