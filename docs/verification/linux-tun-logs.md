# Linux TUN 权限核心日志验收

2026-10-17：Linux root 权限服务的核心校验、运行输出和生命周期日志已传回普通宿主，复用原日志页面、脱敏和增量采集接口。普通宿主 15 个场景及独立 Debian VM 的实际 systemd / polkit 允许与拒绝路径通过。公开 Linux `capabilities.tun` 继续为 **false**；活动桌面认证弹窗和 GUI 服务管理仍未完成。

记录：[证据与源码摘要](linux/logs-evidence.json)、[测试目录](linux/logs-tests.json)、[隔离网络原始输出](linux/logs-namespace-run.log)、[日志压力输出](linux/logs-log-unit-stress-final.log)、[Windows 回归](linux/logs-windows-regression-final.jsonl)。前阶段[安装](linux-tun-install.md)和[普通宿主接入](linux-tun-manager.md)记录保留其原验收范围。

## 实现行为

普通 Manager 使用无 payload 的 `hello-logs` 显式协商日志，私有协议版本仍为 1。旧 `hello` 或直接 `start` 客户端不会收到异步日志。旧权限服务无法协商时，普通宿主明确返回 `tun_service_handshake_failed`，不会假装启动成功或静默失去日志。公共 Flutter 协议未增加字段。

每条权限连接维护独立缓冲，实际捕获核心 `check` / `run` 的 stdout 和 stderr，同时记录中文授权、启动失败、意外退出与恢复状态。复用核心脱敏 writer，并在普通宿主按本次凭据和 API secret 再次清洗；不读取其他用户日志。journal 只写固定阶段标签，原始核心内容和凭据不进入 system journal。

缓冲上限 2,000 条，每批最多 16 条，每 100 ms 至多发送一批。写入核心输出只操作内存，IPC 背压不会阻塞核心。每个日志帧最多写 1 秒；半帧失败会使通道不可复用，并进入恢复确认流程。停止时先真实停止核心和恢复网络，再排出最新两批日志，最后确认停止；跳过积压有明确 dropped 标记。缺少停止回执不能视为恢复成功。

公共日志 ID 和游标由普通宿主重新分配，保留原显示时间。Linux 在记录与清空发生时直接读取同一内核 `CLOCK_MONOTONIC`：清空前排队的记录不能重新出现，清空后立即产生的记录可以保留，墙上时间调整不影响屏障。时钟读取失败时返回 `logs_unavailable`，清空失败保留原记录，后续单次写入成功不会静默清除该错误。

## 实际验收

| 范围 | 结果与限制 |
| --- | --- |
| Linux 隔离网络、IPC、日志、恢复、普通宿主 | 414 个 Go 通过事件，含子测试；使用普通 UID、真实 Secret Service 和锁定核心，activation / 授权器由 fixture 提供 |
| 完整普通宿主 | 15 个场景；新增真实端口占用导致的核心启动失败，日志包含原始故障原因；正常连接验证实际流量日志、清空和清空后的新 DNS 日志 |
| 日志并发与边界 | 20 轮，共 500 个通过事件，单独计数；覆盖脱敏、分片、溢出、末行、无效批次原子拒绝、背压、半帧、旧服务、缺少停止确认和并发停止 |
| 真实 systemd / polkit | 独立 Debian 13、Linux 6.12.113+deb13-cloud-amd64、systemd 257.13-1~deb13u1、polkitd 126；父测试及 allow / deny 共 3 个通过事件，46.66 秒 |
| Windows 锁定核心回归 | 164 个 Go 通过事件；3 项会改变系统代理的条件测试显式跳过 |
| 静态检查 | Windows amd64、Linux amd64 / arm64 的 Go vet，以及 Go 格式、相关 shell / Python 语法通过；arm64 未执行 |
| Flutter | 本阶段没有 Dart 修改或新 Flutter 执行；440 项属于前阶段结果 |

真实 VM 使用 UID 65534 的普通客户端、真正的 socket activation、`pkcheck` 和 polkitd；VM 内仅对指定 UID / action 安装临时 YES / NO 规则。允许时 root TUN 核心实际启动，日志传回并确认断开恢复；拒绝时普通日志显示原因，没有核心或网络变更。检查 system journal 不含核心输出与合成凭据，并完成 idle 和卸载。**未使用桌面认证 agent 或密码弹窗，此结果不代表活动用户认证弹窗已验收。**

隔离 namespace 的接口、双栈路由和规则完整快照逐字节保持，原 authorizer / helper 内容和 metadata 保持，父 WSL 网络未改变，无 fixture namespace 进程残留。真实 VM 的两个 IPv6 RA 路由剩余寿命按实际采集时长自然递减；测试保留全部原始字段，仅核对该递减在内核 USER_HZ 100 的实测时间范围内，其他配置仍逐字段比较。补充回归拒绝寿命重置、过快递减、其他 cache 字段变化、优先级变化和路由增删。

## 失败历史与复验

保留首次清空近似算法丢失紧邻新记录的失败，现改为直接内核时间戳。保留 Windows 夹具端口选择失败，现显式选择并实际检查 TCP / UDP 候选，不跳过协议验收。前两次 VM 功能已通过，但冻结 RA 寿命的原始比较失败，原始前后快照均保留；最终按测量时间校验自然递减。PowerShell 直接传测试正则的失败没有执行测试，不计入通过数量。

Linux amd64 root QA 主机入口为 `bash tools/verify_linux_network.sh --permission-logs`。需要网络工具、D-Bus、gnome-keyring 与 GNOME 设置后端，使用私有挂载的 fixture 授权器。通用 `tools/verify_linux_systemd_vm.sh --permission-logs` 本阶段只做语法检查；本机实际 VM 入口保存在忽略的 `build/qa/linux-logs/vm/`，从旧 QA overlay 派生新 overlay，旧镜像缓存只读，未向 guest 共享宿主凭据、设备或入站端口。

`python tools/finalize_linux_log_evidence.py --vm-results build/qa/linux-logs/vm/systemd-results-1792244959` 校验并封装已有结果，不执行测试。证据包含源码、运行输入和原始产物的 SHA-256；锁定镜像另核对官方 SHA-512。大型 VM、二进制及包缓存只留本地，仓库保存其摘要及验收原始文本。

## 后续边界

活动桌面 polkit 认证 / 取消、GUI 服务状态和安装 / 升级 / 卸载 / 恢复入口、真实核心运行时 systemd 整组终止、Linux GUI / 分发、切网 / 休眠 / 注销、time namespace 与 ARM64 执行仍待验收。macOS 宿主、iOS 扩展及完整 Figma 页面 / 弹窗 / 主题 / 字号对照仍未完成。

本阶段实时读取了 Figma 的桌面概览和日志参考，没有修改设计稿或重新完成全页面视觉验收。未重新打包 Windows 0.1.0+4。FlClash、其服务和用户手机均未操作。
