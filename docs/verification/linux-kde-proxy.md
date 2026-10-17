# Linux KDE 系统代理与跨桌面恢复

日期：2026-10-17。本轮接入 KDE 配置后端、复用用户共享恢复租约，并实际运行 KDE / GNOME 的核心传输与异常恢复测试。证据见 [kde-proxy-evidence.json](linux/kde-proxy-evidence.json) 和 [kde-tests.json](linux/kde-tests.json)。这是隔离设置后端及宿主验收，完整 Plasma 桌面和 Linux Flutter GUI 尚未验收。

## 实现

- `internal/linuxproxy` 统一 GNOME / KDE 的租约，系统代理开关按实际后端能力启用。Linux 状态文案改为“系统代理已就绪”，避免将 KDE 标作 GNOME。
- KDE 使用独立普通用户辅助程序，通过 Qt Core / D-Bus 和 KF6 ConfigCore 处理 `kioslaverc`，固定只修改 `ProxyType`、HTTP / HTTPS / FTP / SOCKS、PAC、例外列表及反向例外开关。认证及 PAC URL 经私有 stdin 传递，不进入 argv 或诊断。
- 相对配置名保留系统默认和锁定项；单文件视图识别本地未设置项。修改以一次 KConfig 提交完成，检查提交结果、读回值，并通知 `/kioslaverc` 的 KConfig 观察者。无关字段允许 KConfig 规范化编码，但实际值保留。
- 所有后端共用用户目录、锁、加密 scope 和日志文件。新日志为 version 2，记录具体后端及 XDG 配置目录绑定；读取旧 version 1 GNOME 日志，沿用原 `gnome-proxy-recovery.bin` 文件名和加密 scope，避免升级遗留接管。
- 切换桌面后按记录中的后端恢复；配置根目录或默认配置目录发生变化时保留日志并报错。第二个活宿主即使来自另一桌面也不能抢占租约。
- 接管前预留完整加密恢复记录的容量，包括允许的最大绕过列表修改；原配置过大时在写系统设置前拒绝接管。取消和不确定写入使用独立清理上下文恢复。

## 实际结果

Windows Go 1.25.5 交叉编译的 Linux amd64 宿主和测试二进制，在 WSL2 的私有 mount namespace / tmpfs 中执行。基础为经校验的 Alpine 3.22.2；APK 签名验证通过，普通 UID 1000、独立会话总线、XDG 目录和临时 Secret Service。Qt 6.8.3、KConfig 6.13.0、libproxy 0.5.10。仅提取签名包的 ConfigCore 运行库和匹配开发头文件，不执行 KDE GUI / QML。生产 CMake 构建成功，启用 `-Wall -Wextra -Werror`。

| 检查 | 结果 |
| --- | --- |
| Linux Go | 242 个通过事件，包含父 / 子用例与单独锁定密钥环测试；2 个主批次跳过项在证据中说明 |
| 独立消费者 | libproxy 实际解析 HTTP / HTTPS / FTP / SOCKS 到 RainLink，本机地址直连；恢复无配置后为直连 |
| 原配置保留 | 认证 URL、PAC、绕过列表、未设置项、系统默认及无关字段实际值保留；首次无文件时只读能力检查不创建配置 |
| 变更通知 | 独立 D-Bus 监听收到 `/kioslaverc` 的 `ConfigChanged`，独立 `kreadconfig6` 回读有效值 |
| 完整宿主 | KDE 和 GNOME 分别验证开关与断开、EOF、强杀宿主、强杀核心、watcher 重启；每种场景都传输真实核心 fixture 字节并确认端口释放 |
| 会话与故障 | 跨桌面活宿主租约冲突、测速不干扰、跨桌面恢复、旧版日志、绕过列表编辑、后来代理所有者、配置目录改变、只读失败后重试、日志篡改及取消通过 |
| 锁定和特殊配置 | 系统不可变默认、本地锁定项、受管理字段的展开 / 本地化 / 删除标记拒绝接管，原文件不变 |
| Windows 回归 | 162 个 Go 通过事件；3 项写当前系统代理的显式测试跳过。FlClash 保持关闭，没有操作其服务 |
| 共享 UI 协议 | 8 项 Flutter 测试、静态分析及修改文件格式检查通过；此前 440 项全量仍是上轮记录，本轮未重复全量 |
| 静态检查 | Windows amd64、Linux amd64 / arm64 `go vet`，Go 格式和三个 Bash 脚本语法检查通过；arm64 未执行 |

本轮核心锁值不变；网络验收使用本地可控服务端，不新增真实机场外网通过声明。未运行 race detector。此前 Windows 0.1.0+4 交付包保持原样，本轮没有生成新的完整 Linux 安装包或 Windows 版本。

## 在 Linux 复验

在 GNOME 验收所需的 Go、Python、D-Bus、GNOME Keyring、libsecret、gsettings / dconf / schemas 之外，安装上述 KDE 构建依赖、`kreadconfig6`、`dbus-monitor` 和 libproxy 运行库：

```bash
bash tools/build_kde_proxy.sh
bash tools/verify_linux_session.sh --kde
```

验证脚本隔离 HOME、全部相关 XDG 数据路径、默认配置和会话总线，不使用当前桌面的密钥环或代理配置。原生 `go test` 的临时目录由测试代码放入显式指定的 QA 辅助程序；生产代码仍只查找宿主旁的可执行文件，没有测试环境变量发现路径。

本次实际执行了 CMake 和专用 chroot 运行器、全部交叉编译测试二进制；两个 Bash 入口已作语法检查，尚未在 Linux 原生 Go 工具链上从头运行完整入口。构建及测试日志在 `build/qa/kde`，证据绑定源码、工具、包清单和二进制摘要。

## 待验收

真实 Plasma / GNOME 会话和应用、KDE 5、Ubuntu 各版本、注销 / 重启 / 休眠 / 切网、ARM64 实机、长时恢复及发行包。Linux TUN、Flutter GUI 与全部页面 Figma 对照、托盘 / 自启 / 更新和安装分发仍未完成。受管理字段的特殊 KConfig 标记继续按明确不支持处理；本轮没有新增 Linux GUI 截图。
