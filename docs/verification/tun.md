# Windows TUN 验收

日期：2026-10-17。Windows 11、本机管理员环境、锁定核心 `1.12.25-rainlink.1`。本轮使用隔离测试数据库与本机 HTTP/SOCKS5 上游，不读取用户订阅或更改用户节点，不代表公网服务商测试。

## 操作与实现

- 在「概览」选择系统代理与 TUN，可单开或同时开启；一个核心提供混合入站与虚拟网卡。未连接时只保存选择，点击「开始连接」才实际接管。
- 已连接时切换 TUN，会断开并使用原活动节点或代理链、规则快照、模式、网络设置重新连接。节点页改选尚未应用的目标不会混入这次重连；修改失败时尝试恢复原连接，失败如实显示。
- GUI 与普通 Go 宿主继续使用私有 stdio。TUN 通过 `runas` 启动同一宿主的固定 `tun-core` 子命令，GUI 无需整体提权。授权限时 90 秒，用户可取消；实际 UAC 确认与拒绝仍需标准用户环境验收。
- 权限进程与宿主通过随机命名管道通信，DACL 仅限当前用户、管理员和 SYSTEM，并双向核对 PID 与同一可执行文件。配置只在管道及 stdin 传递，不保存明文配置或写入命令行。权限进程只运行旁边 SHA-256 匹配的固定核心，验证期间拒绝核心文件被替换。
- 权限进程先加入带退出清理的 Windows Job，子核心继承保护，避免在启动与加入 Job 之间出现无保护的 TUN。普通宿主 EOF/退出、权限进程退出、核心退出均结束本次运行。全局内核租约防止两个 RainLink TUN 同时接管。
- 使用唯一 `RainLink-*` 网卡名称、IPv4/IPv6 地址，冲突时拒绝连接；核心出口和 DNS socket 绑定上游接口，链的后续跳仍走上一跳。DNS 拦截先于用户分流及全局/直连模式；双栈路由实际存在才回报 TUN 开启。停止后确认网卡消失，未确认清理则保留可重试错误。

## 实机证据

`tools/verify_tun.py` 的八个场景见 [windows-evidence.json](tun/windows-evidence.json)。测试使用生产 TUN 配置，独立看门狗只持有核对了完整路径的测试宿主句柄，35 秒超时退出该宿主。每个场景核对网卡、活动路由、DNS 与原始系统代理恢复一致。

| 场景 | 验收内容 |
| --- | --- |
| disconnect | 未设置代理的 TCP 请求经 TUN 到达本机 HTTP 上游；正常断开恢复 |
| coexist | TUN 与系统代理共用一个核心；断开后代理恢复 |
| eof | 关闭私有输入管道后清理 |
| host-crash | 强制退出自身测试宿主，权限进程与核心退出并恢复 |
| guardian-crash | 强制退出对应权限进程，Job 回收核心并恢复 |
| core-crash | 强制退出对应核心，宿主报告中断并恢复 |
| udp-dns | 无代理 UDP 经 TUN 和 SOCKS5 上游往返；UDP DNS 被接管并由保存的解析策略回答 |
| cancel | 一次写入连接与取消请求，排队操作也被取消，不能迟到启动 TUN |

Flutter 原生集成 `app/integration_test/windows_tun_test.dart` 从实际概览点击开启、连接、关闭/重开 TUN、断开，核对宿主观测与真实 TCP 传输。将节点选择改为 B 后切换 TUN，实际目标仍为原 A。使用临时 SQLite，见 [flutter-evidence.json](tun/flutter-evidence.json) 和 [overview-native.png](tun/overview-native.png)。

实际 Release 包内宿主也通过 TCP 与 UDP/DNS 测试，见 [packaged-host-evidence.json](tun/packaged-host-evidence.json)。另有连续 10 轮交替进程异常退出及 UDP/DNS 重连全部通过，每轮网络与代理均恢复，见 [endurance-evidence.json](tun/endurance-evidence.json)。早期快速重启测试曾出现一次 `core_not_ready`，当次已停止并清理，单项重试和后续完整/连续测试均未复现；根因尚未确认，不能据此宣称长期稳定性问题已排除。

Windows Release 预览包为 `build/RainLink-windows-x64-tun-preview.zip`，SHA-256 为 `c6bf6003d4e6b6bbaad4bb501cab83bb802db94496a38c1d698e2aad17d0d7c6`，75 个条目已通过 ZIP CRC 与 Release 引擎校验。实际打开并正常关闭了该 Release，用户 68 个节点、1 个分组、设置、启动项和系统代理的前后摘要一致，见 [release-evidence.json](tun/release-evidence.json)。FlClash 辅助服务保持原状态，未启动或修改它。

自动测试还覆盖授权失败回退、切换取消后迟到回执、TUN 偏好兼容旧格式、状态类型与网卡回执、受控编译与隔离测速禁止接管。静态检查与测试日志位于 `build/tun-*.log` / `build/tun-go-final.jsonl`。

## 视觉依据与依赖

本轮通过 Bridge 实时读取 RainLink 文件 `unsaved-mva99nf3-128z4u3c`，导出桌面概览 `2:17066` 与移动首页 `2:22537`：`reference/overview-*-tun-20261017.png`。保留原 Figma 图标、开关尺寸和紧凑概览布局，启用能力来自宿主回执。移动布局仍独立，原生 TUN 未接入的平台开关禁用。

核心内嵌的 Wintun 0.14.1 amd64 与官网 ZIP 中的 DLL 逐字节一致，摘要 `e5da8447dc2c320edc0fc52fa01885c103de8c118481f683643cacc3220dafce`。`tools/runtime-licenses.lock.json` 锁定官网归档、DLL 与许可证摘要，`setup_runtime_licenses.py` 校验并将 Wintun 和 go-winio MIT 许可复制至发行包与关于页。无需运行时下载驱动 DLL。

## 尚未验收

标准用户实际 UAC 同意/拒绝、IPv6 公网传输、休眠恢复/上游网卡切换、多用户会话、其他网络安全软件与长期运行尚未完成；当前固定上游接口变化后需要重连。其他桌面平台、两端移动服务、签名安装和服务化仍按实现清单继续，不能据本轮结果宣称跨平台软件完整交付。
