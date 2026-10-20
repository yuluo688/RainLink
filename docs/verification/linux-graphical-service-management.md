# Linux 活动桌面授权与服务管理

日期：2026-10-20。基于 `0f80987cac940518e77f23816c5490223debff76` 与未提交修改，延续[真实替换期间取消](linux-broker-write-cancellation.md)。完整五平台开发目标仍在进行。

## 实际环境与范围

本轮使用独立 Debian 13 虚拟机，运行真实 systemd、logind、polkitd 126、X11/Openbox、lxpolkit 和 Mesa 软件渲染。第一阶段 RainLink 以 UID 2000 运行，最终包在新 overlay 的 UID 2001 与全新 home/keyring 中运行；PAM 登录会话归属 seat0、tty8，`Active=yes`、`Type=x11`、`Remote=no`。虚拟机没有共享宿主目录、用户凭据或设备，没有入站网络端口。前期下载发行版软件包使用虚拟机用户网络。

VM 专用规则对固定测试用户及 `/proc/<pid>/exe` 的 pkexec 请求要求 `AUTH_ADMIN`，并将临时 QA 用户设为认证身份。密码仅在 VM 内随机生成，通过实际 lxpolkit 密码框输入；应用和生产管理通道都不处理密码。此结果覆盖该 X11/Openbox/lxpolkit 登录会话，完整 GNOME、Plasma、Wayland、其他发行版和物理设备继续验收。

首次启动因缺少 `libEGL.so.1` 在打开窗口前中止。补装 `libegl1`、`libgl1`、`libgles2` 后实际窗口正常，README 已补齐 Debian 13 的运行依赖；补装和 systemd 会话日志保留在本阶段证据中。

## 发现并修复的问题

活动登录会话给进程继承了 `CAP_WAKE_ALARM`。pkexec 清除该能力后无法读取仍带能力的普通 broker 的 `/proc/<pid>/exe`，在认证前返回 `Permission denied`。普通用户服务管理进程现在先清除全部 Go 线程上的 ambient、permitted、effective 和 inheritable 能力，再进入原管理通道。root worker 的授权与安装路径继续由原有 pkexec 和固定动作管理。

Linux 开发脚本显式使用 `CGO_ENABLED=0` 构建宿主，让 `AllThreadsSyscall` 可以覆盖所有运行时线程。新增回归由 root 测试进程给 UID 65534 子进程授予 ambient 能力，再进入生产 `Serve`，逐一检查 **9 个 OS 线程**的四组能力均为空。管理单元顶层 **7 项通过、6 项 fixture 跳过**；Linux 交叉编译与 Go vet 通过。实际桌面会话另确认了权限框出现及成功授权。

lxpolkit 取消密码框时，本环境的 pkexec 返回 127 和 `Not authorized`。提示改为“未获得系统授权，请重试或检查桌面认证服务”，避免把取消一概描述为系统故障，也不把未授权当成成功。

## 实际界面闭环

| 操作 | 结果与系统回读 |
| --- | --- |
| 取消应用内安装确认 | 保持 `missing`，没有安装文件 |
| 在实际系统密码框取消 | 返回未授权，保持 `missing` |
| 输入 VM 随机密码安装 | polkit 记录一次性授权成功；界面回读 `current`、`enabled=true`、`active=true` |
| 核对安装结果 | 宿主与锁定核心的 SHA-256 与应用目录一致，socket 实际 active / enabled |
| 从界面确认并授权卸载 | 回读 `missing`、enabled / active 均为 false；宿主、核心和服务单元已移除 |
| 等待认证时点击“取消操作” | 系统认证框关闭，界面显示已取消，没有安装文件 |
| 等待认证时关闭应用窗口 | 应用退出 0，认证框和管理子进程均退出；最终只保留安装锁文件，没有事务或临时文件 |

第一阶段安装/卸载闭环使用能力修复宿主 `17fe06d8…`；修改未授权文案后，交叉构建宿主 `20640cd8…` 实际重新启动，通过系统取消、应用内取消、等待认证时关闭及最终清理检查。两份构建的验证范围分别保留在[证据索引](linux-graphical-service-management/evidence.json)。下方最终完整包另执行了一次安装与卸载，没有用第一阶段结果代替。

- [真实系统认证框](linux-graphical-service-management/polkit-authentication.png)
- [安装成功并回读系统状态](linux-graphical-service-management/installed.png)
- [卸载后的真实界面](linux-graphical-service-management/uninstalled.png)
- [最终未授权提示](linux-graphical-service-management/authorization-dismissed.png)
- [应用主动取消](linux-graphical-service-management/application-cancelled.png)
- [活动会话信息](linux-graphical-service-management/final-login-session.log)
- [polkit 原始日志](linux-graphical-service-management/polkit-journal.log)
- [最终状态与无残留确认](linux-graphical-service-management/final-status.json)

## 最终完整包验收

Linux 原生重新构建的 **0.1.0+4** 包已替换本地默认路径 `build/RainLink-linux-x64-preview.tar.xz`，大小 **32,206,576 bytes**，SHA-256 为 `aaea75eee68c564655864cd9b0b191cf440958d88b67b7feb9af5ec2f6488e7e`。733 项源码/资源和 181 项原生/构建输入与当前工作区一致；77 项归档载荷、55 项运行资源及锁定核心摘要通过。与上一预览相比[仅宿主载荷改变](linux-graphical-service-management/package-delta.json)，原有 AOT、引擎和资源逐字节相同。

新 VM 直接解压完整包，未替换其中任何二进制。普通用户实际打开 960×640 窗口，经应用确认和 lxpolkit 密码框安装后，UI 与系统回读均为 `current`、`enabled=true`、`active=true`。安装宿主 SHA-256 为 `3c94988871e41f58fcfa486b7c58ce749b1b2cac6a217ffa9c1cf586f46394e4`，核心为 `640e5293d90b94c71318031284e65cf8121d99ee9c06482f021ed77c9f3fa96d`，都与包中原文件一致。Linux 原生副本没有 Git 元数据，因此宿主摘要与前述 Windows 交叉构建不同；版本与纯 Go 设置已留存。

同一窗口再次确认并输入系统密码卸载，回读 `missing`，文件、单元和待恢复事务均移除。最后从右上角关闭应用，退出 0，无认证窗口、应用、pkexec、宿主或核心进程残留；只保留安装锁文件。VM 完成标记为 0 并正常关机，构建用私有 chroot 会话也已退出。polkit 日志确认该最终包有两次独立的一次性密码授权。

- [最终包安装成功](linux-graphical-service-management/canonical-package/canonical-installed-window.png)
- [最终包系统密码框](linux-graphical-service-management/canonical-package/canonical-polkit-install-window.png)
- [最终包卸载后的界面](linux-graphical-service-management/canonical-package/canonical-uninstalled-window.png)
- [安装状态与文件摘要](linux-graphical-service-management/canonical-package/installed-status.json)
- [卸载回读](linux-graphical-service-management/canonical-package/uninstalled-status.json)
- [关闭后的最终清理](linux-graphical-service-management/canonical-package/final-status.json)
- [最终包真实授权日志](linux-graphical-service-management/canonical-package/polkit-journal.log)

## Figma 与继续范围

实时读取 RainLink 的三个 Figma 页签及桌面设置节点 `2:19743`，保存[当前参考画面](linux-graphical-service-management/figma-settings-current.png)。从 manifest 对应节点重新原生导出的 [44 个 SVG 与运行资源逐字节一致](linux-graphical-service-management/figma-icon-audit.json)。应用继续使用六分类侧栏及现有 Figma 图标。Linux 当前通用设置按已实现的平台能力呈现，尚未补齐设计稿中的托盘、开机启动和通知等全部行为；服务管理卡属于新增的 Linux 平台功能。本阶段未重新运行此前的 468 项 Flutter 或 108 张布局截图，也没有把这些旧结果计作本轮测试。

公开 Linux `capabilities.tun` 仍为 **false**。此处服务安装成功不表示已经开放产品 TUN 连接；当前最小图形 VM 的系统代理能力也为 false。

正常退出仍记录 `atk_socket_embed`、`FlutterEngineRemoveView`、`g_object_weak_unref` 和失效 `FlBinaryMessenger` 诊断，原文见[第一阶段应用日志](linux-graphical-service-management/rainlink.log)与[最终包应用日志](linux-graphical-service-management/canonical-package/rainlink.log)。这些 GTK/Flutter 诊断尚未定位；退出 0 和无残留并不证明它们已经解决。

完整桌面/发行版兼容、正式分发、Linux 通用系统功能、macOS 宿主、iOS 网络扩展、Android 真机及完整弹窗视觉继续按[实现清单](../IMPLEMENTATION_STATUS.md)推进。

## 复现入口

本次执行的 bootstrap、会话、控制和点击脚本保存在证据目录，带本机路径的控制脚本仅用于审计本次运行。可复用 VM 准备入口为 `tools/fixtures/linux_graphical_management_guest.sh` 与 `linux_graphical_management_session.sh`：在独立 systemd QA VM 的 CIDATA seed 中放入 `rainlink-preview.tar.xz` 和会话脚本，以 `RAINLINK_TEST_GRAPHICAL_MANAGEMENT=disposable-vm` 执行 guest 脚本。它创建临时用户、登录会话、密码和 VM 认证规则，等待通过图形界面或 QGA 执行上述步骤；完成后在 VM 内创建 `/run/rainlink-gui-finish`，收集日志并正常关机。

两份复用脚本已补齐本轮发现的图形依赖并通过 shell 语法检查；本次实际运行的是证据目录保存的交互脚本，没有将复用脚本声明为已重新执行的全自动验收。没有提交、推送或发布本轮修改。
