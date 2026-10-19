# Linux 等待系统认证时取消

后续已修复安装提交前的取消边界，并完成五种真实 systemd 写入后取消/提交保持场景，见[安装取消与恢复](linux-install-cancellation.md)。本页及摘要保持此前授权取消检查点的范围。

2026-10-20。本轮接续[服务管理与安全退出](linux-tun-service-management-acceptance.md)，修复等待系统认证时仅关闭输入管道、认证请求仍可能挂起的问题。前轮记录和源码摘要保留原范围。

## 修改

普通用户取消服务管理时，先关闭控制管道撤销安装，再对已启动的授权进程发送 SIGTERM。`pkexec` 等待认证时不读取标准输入，此时真实 UID 仍为调用用户，能够接收该用户的终止信号。授权后切换为 root 时，普通用户发送信号的 EPERM 属于预期；root worker 继续依靠管道 EOF 取消，并等待有界恢复完成。不会用 SIGKILL 强制中断正在写入的 root 安装。

该授权阶段和 UID 行为也对照了本轮 guest 对应的 [polkit 126 pkexec 源码](https://github.com/polkit-org/polkit/blob/126/src/programs/pkexec.c)；实际验证结果见下文，不把源码推断替代为运行证据。

服务管理仍保留原操作的结果；“取消请求已确认”不代表原操作结束。退出也继续等待原操作及状态回读。公开 Linux `capabilities.tun` 保持 false。

## 实际验证

在独立 Debian 13 / Linux 6.12.113 / systemd 257 / polkitd 126 VM 内，普通 UID 65534 运行生产宿主，通过真正的 `pkexec` 向真正的 polkit 发起 AUTH_ADMIN 请求。测试代理只注册到该 broker 的 Unix process subject，不读取密码，也不模拟登录桌面。规则仅作用于 VM 内的固定 UID、action 和程序。

| 场景 | 实际回执 |
| --- | --- |
| 应用取消 | 已进入 BeginAuthentication 后发出取消；先收到请求确认，原操作返回 cancelled；认证代理收到真正的 CancelAuthentication |
| 通道 EOF | 等待认证时关闭通道，broker 保留失败退出；认证代理收到 CancelAuthentication |
| 认证代理拒绝 | 代理返回取消，原操作返回 authorization_cancelled |

三种场景均确认服务仍为 missing，没有生成安装事务。取消后的 broker 在 5 秒上限内退出；三项及其顶层测试耗时分别为 1.75 / 1.19 / 1.17 秒及 5.74 秒。

修改后的宿主还通过原来的五种真实管理场景：拒绝、安装/恢复/重复安装/卸载、不同构建替换并保留 disabled/inactive、授权后安装锁等待时取消、同位置 EOF。顶层耗时 188.79 秒。后两项仍限于事务写入前，不代替写入期间取消的验证。

Linux 管理单元 6 项通过，4 个测试 fixture 默认跳过。新增回归启动真正的不读取输入的子进程，要求取消使其以 SIGTERM 结束，不能依靠超时后的 SIGKILL 才退出。该断言在 VM 二进制生成后收紧，随后单独编译并运行；生产取消逻辑和 VM 场景没有因此改变。Go 格式及 Linux 管理/安装静态检查通过。

没有重新执行 Flutter 全量或视觉测试；前轮 460 项、40 张 fixture 和 44 个 SVG 的证据继续保持其当时源码与布局范围。

## 证据与复现

实际日志、依赖签名索引复核、源码和二进制摘要见 [linux-service-management-auth/evidence.json](linux-service-management-auth/evidence.json)。guest 原始 cloud-init 输出含临时 SSH host key，未复制到公开证据目录。VM 使用只读 QA 基底和新 overlay；未共享宿主凭据、目录、设备或入站端口。实际运行仍为隔离 Alpine/QEMU 包装入口，通用 Linux QA runner 本轮没有整份直接运行。

```sh
# Linux QA 主机，运行整个真实管理和认证协议测试。
bash tools/verify_linux_systemd_vm.sh --service-management

# 管理单元默认不请求系统认证。
cd native/host
go test ./internal/linuxmanage
go vet ./internal/linuxmanage ./internal/linuxinstall
```

固定依赖包含 QA 专用的 `pkexec` 和 `python3-dbus`；宿主下载核对锁定 SHA256，guest 再与签名 apt 元数据核对后安装。测试代理通过 D-Bus 协议验证取消，不证明活动桌面上的图形认证窗口、密码输入及完整桌面生命周期。下一步继续写入期间取消、图形桌面、分发和其他平台，完整五平台目标仍在进行。
