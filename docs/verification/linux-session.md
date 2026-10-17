# Linux 宿主与 GNOME 系统代理验收

最新 KDE 续验见 [Linux KDE 系统代理与跨桌面恢复](linux-kde-proxy.md)：两套后端已统一恢复租约，242 个 Linux Go 通过事件及 162 个 Windows 回归事件通过。本文保留初始 GNOME 阶段的实现与验证快照；下文“未完成 KDE”属于该历史阶段。

日期：2026-10-17。本阶段完成 Linux amd64 本地代理宿主与 GNOME 系统代理的隔离验收。最新结果见 [GNOME 验收摘要](linux/gnome-proxy-evidence.json)和[测试明细](linux/gnome-tests.json)，绑定本轮实际宿主、核心、测试二进制及源码摘要。初始本地代理阶段的 [native-evidence.json](linux/native-evidence.json)作为历史记录保留，其中源码摘要与计数属于当时版本。

## 已实现

- 核心构建支持指定平台。Windows 原有锁值保持不变，Linux amd64 有独立 SHA-256；宿主白名单按 OS / CPU 选择，两平台输出许可证和对应源码。
- Linux 查找宿主旁的 `sing-box`，通过私有 stdio 支持凭据、连接、模式、规则、代理链、设置和诊断。未知桌面及 KDE 返回 `connect=true, systemProxy=false, tun=false`；验证通过的 GNOME 返回 `systemProxy=true`。TUN 继续关闭。
- 凭据使用 AES-256-GCM、随机 nonce 与记录 ID 绑定；SQLite 保存密文，32 字节主密钥保存在 Secret Service。`secret-tool` 只通过 stdin 接收主密钥，没有明文备用文件。仅在不解锁的 `search --all` 确认没有条目后，才允许创建密钥或报告丢失，避免把锁定误判成丢失。
- 操作处理取消、超时和实际输出上限，诊断不进入 UI。私有目录 0700、普通文件 0600，使用目录描述符、`openat`、禁止跟随链接、文件身份检查、可取消 `flock` 及原子写入。安全存储和系统代理复用该文件层。
- Linux 核心使用 `Pdeathsig`；创建核心的 OS 线程保留至回收，避免 Go 线程结束误杀活动核心。宿主异常退出时核心随之退出。

## GNOME 接管与恢复

GNOME 接管要求 `XDG_CURRENT_DESKTOP` 包含 GNOME（允许 `ubuntu:GNOME`）、会话 D-Bus、`gsettings`、`dconf`、`gdbus`、GNOME 代理 schema 可写及 pidfd 可用。凭据和恢复记录依赖可用的 Secret Service。条件不足时不开放首页系统代理开关，本地端口仍可用。

接管通过一次 dconf changeset 设置 HTTP/HTTPS/SOCKS 回环端点，关闭旧 FTP 路由和原代理认证，绕过本机地址。写入前保存加密恢复记录，写入后读取实际值确认。还会核对 dconf 服务的 PID、用户和配置目录，拒绝 memory backend 与客户端/服务配置目录不一致的环境，避免读写不同数据库。

恢复租约位于全用户共享的 `$XDG_STATE_HOME/RainLink/system-proxy`，缺省为 `~/.local/state/RainLink/system-proxy`；不同 checkout 不能同时接管。日志绑定目录身份，所有者绑定 PID、启动时钟和 boot ID，避免 PID 复用。原代理认证等敏感值只保存在密文中。

独立 watcher 先通过 pidfd 确认已监控宿主，再向宿主发送就绪确认，之后才允许接管。它独立于核心的父进程退出信号，在宿主强退后恢复代理；结束的 watcher 可重新创建。正常断开、关闭开关、EOF 和核心退出也执行恢复。测速进程不会读取或恢复主会话租约。

恢复保留原先未设置的项目、无关配置及用户后来单独编辑的绕过列表；另一客户端改写路由后保留其设置。恢复包含 reset 时，先持久保存目标，部分完成后仍可继续；失败或密钥环不可用时保留日志及错误，后续重试。没有提供静默解锁密钥环的备用方式。

## 实际验证

使用 Windows Go 1.25.5 交叉编译，在 WSL2 实际执行。基础为经 SHA-256 校验的 Alpine 3.22.2、经 APK 签名验证的 libsecret 0.21.7、GNOME Keyring 48、D-Bus 1.16.2、GLib 2.84.4、dconf 0.40.0、GNOME schemas 48。测试以 UID 1000 执行，使用独立总线、临时 HOME/XDG、dconf 配置和密钥环；临时文件系统位于私有挂载命名空间的内存文件系统中。

| 检查 | 结果 |
| --- | --- |
| Linux Go 测试 | 222 个通过事件，包含父/子用例；97 个顶层通过。Windows 专属上游选择用例跳过；锁定密钥环用例在主批次跳过后单独通过 |
| GNOME 实际设置 | dconf 写入和 15 项 GSettings 有效值回读通过；原 PAC、认证、绕过列表、未设置项目和无关项恢复通过 |
| GNOME 完整宿主 | 本地连接后开关、连接时启用、正常断开、EOF、强杀宿主、强杀核心、watcher 重启均通过；每种场景均通过真实核心传输本地 fixture 字节 |
| 会话隔离 | 活着的另一宿主不能抢占全用户租约；独立测速进程握手与退出不改变主连接接管 |
| 故障与恢复 | 取消、部分应用、读回失败、部分恢复后重试、后来的代理所有者、日志篡改/目录绑定、密钥不可用后重试均通过；memory backend 和配置目录错配保留日志并拒绝恢复 |
| 真实 Secret Service | 保存/读取、丢失密钥只读失败、新密钥不能解密旧记录、真实锁定时读写失败通过 |
| 实际核心 | 八协议、TLS/认证失败、代理链和规则、UDP、DNS、在线配置回滚通过，均为本地服务端 fixture |
| 生命周期 | 宿主强退后核心退出；正常退出、EOF、核心异常后本地端口可重新绑定 |
| Windows 回归 | 162 个通过事件；3 项修改当前 Windows 系统代理的 opt-in 测试未开启。本轮未操作 FlClash 或其服务 |
| 共享代码 | 405 项 Flutter 全量测试及最后 8 项状态协议测试、静态分析、257 个 Dart 文件格式检查通过 |
| Go 检查 | Windows、Linux amd64/arm64 宿主和 Android arm64 移动模块 `go vet`、`gofmt` 通过；arm64 未执行二进制 |
| 清理 | 测试密钥环、总线、核心与 watcher 均结束，临时挂载与空目录已移除 |

Linux 核心 SHA-256：`ce9bb3e44c9b7e7869bd47f8523a22a148e2ff013ae96787558a3fbdd0661d82`。本轮不改变锁定核心，未运行 Go race detector。

## 在 Linux 复验

安装 Go、Python 3、`dbus-run-session`、`dbus-send`、`gdbus`、GNOME Keyring、libsecret 的 `secret-tool`、`gsettings`、`dconf` 和 GNOME desktop schemas 后运行：

```bash
python3 tools/setup_core.py --platform linux-amd64
bash tools/verify_linux_session.sh
```

脚本在独立总线中提供 GNOME 设置后端，使用临时 dconf 和密钥环，结束后清理，日志位于 `build/qa/linux`。配置目录在启动 D-Bus 前设置，保证激活的服务和测试进程使用相同目录。本次完成该脚本的 Bash 语法检查；WSL 实际验收使用上述依赖、预编译测试二进制与专用 chroot 运行器，没有在 Linux 原生 Go 工具链上完整执行该脚本。

## 尚未完成

KDE 系统代理、Linux TUN 授权/网卡/路由恢复、托盘/自启/更新/安装分发、真实 Linux 桌面 Flutter 启动与 Figma 对照。GNOME 当前验证了实际设置后端和宿主，没有验证真实 GNOME 桌面会话、注销、重启、锁屏/休眠及长期恢复。Linux ARM64、真实机场、切网和正式性能未验收。本轮没有重新读取云端 Figma，也没有新增 Linux GUI 截图。
