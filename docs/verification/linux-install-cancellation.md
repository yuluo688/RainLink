# Linux 安装写入后的取消与恢复

2026-10-20。修复 Linux 安装在版本清单写入后、正式提交前可能漏掉取消的问题。安装现在在各持久写入边界检查 context：提交前取消恢复原文件、清单与服务状态；提交后取消保留已经提交的版本，完成清理并保留取消结果。

接续[等待认证取消](linux-service-authentication-cancellation.md)和[服务管理与安全退出](linux-tun-service-management-acceptance.md)。此前各检查点及摘要不随后续源码修改。

## 回归与实现

先增加回归，实际观察到 `upgrade-disabled/manifest` 在取消后返回 nil；原失败日志保存在 [cancel-boundary-before.log](linux-install-cancellation/cancel-boundary-before.log)。修复后，安装、启用/禁用状态下的升级与卸载，在 journal、停止服务、五个目标文件、启动服务、版本清单及提交记录共十个边界全部通过，合计 50 个取消场景。

提交前观察到取消时，原错误仍为 context.Canceled，恢复使用独立期限。提交记录已经持久化时，恢复依据该记录完成新版本清理，不回滚已确认的版本。恢复失败继续保留事务和备份，不能用虚假成功覆盖错误。

安装模块整套检查有 141 个 Go 通过事件、15 个顶层通过、3 个环境 fixture 跳过；包含上述 50 个取消场景及原有 30 次进程 SIGKILL 恢复。管理模块 6 项通过，4 个 fixture 默认跳过。Go 格式、Linux 管理/安装静态检查、测试和宿主交叉编译通过。

## 真实 systemd 验证

本轮在独立 Debian 13 / Linux 6.12.113 / systemd 257 VM 中，用真实目标文件、安装宿主、核心和 socket 验证下列五项，顶层测试耗时 244.39 秒。测试在安装器的私有 checkpoint 调用 context cancel，取消前读取真实目标文件摘要和持久记录；生产程序没有外部故障注入参数。

| 操作与取消位置 | 实际观察与结果 |
| --- | --- |
| 安装 / file-0 | 第一份宿主文件已写入；取消后回到无服务状态，清单、事务和暂存全部清理 |
| 安装 / manifest | 五个目标文件和版本清单已写入、尚未提交；取消恢复为无服务状态 |
| 禁用状态升级 / file-1 | 宿主与核心写入后取消，旧版本摘要恢复，socket 保持 disabled/inactive |
| 启用状态卸载 / file-2 | 宿主、核心和 socket 文件已删除后取消；恢复旧文件及 enabled/active，真实 socket 就绪探测通过 |
| 禁用状态升级 / committed | 新版本已经提交；取消保留新宿主摘要，socket 仍 disabled/inactive，并完成事务清理 |

不同版本使用有效宿主的不同 Go build ID，证明文件替换与状态保持，不代表真实旧版数据库或协议迁移。

这是实际安装器和 systemd 的取消恢复验证；取消由测试内部 context 注入，**尚未证明普通用户 broker 的取消恰好在实际文件写入中到达**。普通用户经 pkexec 的取消仍由下面的独立场景验证，不把两种证据混为一次端到端操作。

## 授权与管理回归

同一份新宿主还通过普通 UID 65534 的五项真实管理场景：拒绝、安装/恢复/重复安装/卸载、不同构建替换、授权后锁等待时取消及 EOF，顶层耗时 170.73 秒。AUTH_ADMIN 的应用取消、EOF 和认证代理拒绝三项也通过，顶层耗时 5.53 秒。协议代理不读取密码，没有验证活动桌面的图形认证窗口。

同一生产宿主在 WSL 下执行只读 status，核心为 ready，版本 `1.12.25-rainlink.2`，公开 `capabilities.tun` 为 false，见 [write-host-status.json](linux-install-cancellation/write-host-status.json)。该状态输出来自 WSL，不能据此推断 Debian VM 或桌面的系统代理能力。

## 证据与未完成范围

日志、五份取消时的文件摘要、恢复后的清单和服务状态、原始回归失败、锁定依赖复核、源码与二进制摘要见 [evidence.json](linux-install-cancellation/evidence.json)。当前原生与 QA 的 175 份源码输入均与 VM 构建快照一致。

实际运行使用私有 WSL mount/PID namespace 中的临时 Alpine 3.22.2 / QEMU 10 TCG；Debian 使用只读 QA 基底和新 overlay，没有共享宿主目录、设备、凭据或入站端口。通用 QA runner 的实际内嵌下载检查及 Git Bash 语法检查通过，完整通用 Linux runner 本轮没有直接运行。guest 含临时 SSH host key 的 cloud-init 输出不复制到公开证据目录。

```sh
# Linux QA 主机；包含授权/管理及持久写入取消两套真实测试。
bash tools/verify_linux_systemd_vm.sh --service-management
```

本轮没有 Dart/UI 改动，没有重新执行 Flutter 或视觉；前轮 460 项、40 张 fixture、44 个 SVG 比对保留其原范围。Linux 图形认证与完整 GUI、普通 broker 写入中取消、桌面生命周期、正式分发、macOS/iOS 原生实现、Android 真机及最新 Figma 全页面核对继续进行。公开 Linux TUN 保持关闭，完整五平台目标未完成。
