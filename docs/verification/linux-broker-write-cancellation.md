# Linux 普通用户在实际替换期间取消

日期：2026-10-20。接续[安装取消与恢复](linux-install-cancellation.md)，补上普通用户通道在真实目标文件已经替换后的端到端证据。此前的报告与摘要保持原样。本阶段只增加验收和复现入口，没有修改生产安装器，也没有重新打包应用。

## 实际验证

独立 Debian 13 / Linux 6.12.113 / systemd 257 / polkitd 126 VM 中，UID 65534 的生产 `manage-tun-service` broker 经实际 `pkexec` 启动 root worker。内核 fanotify 暂时拦住旧核心 inode 的一次打开：此时新宿主已经安装，第二份核心临时文件已完整写入并 fsync，持久事务仍未提交。普通用户随后发出取消或关闭通道；测试确认真实控制管道已经撤销、root worker 仍在文件操作中，再放行内核事件并等待恢复结束。

该控制只存在于独立 VM 的测试进程，生产宿主和安装器没有新增参数、环境变量或故障注入开关。VM 专用 polkit 规则按固定用户、action 和 `/proc/<pid>/exe` 放行；本阶段不代表密码输入或图形认证窗口验收。

| 原服务状态 | 取消方式 | 验证结果 |
| --- | --- | --- |
| disabled / inactive | 普通通道 cancel | 原操作返回 cancelled，旧宿主及清单恢复，服务仍为 disabled / inactive |
| disabled / inactive | 普通通道 EOF | broker 保留失败退出，旧宿主及清单恢复，服务仍为 disabled / inactive |
| enabled / active | 普通通道 cancel | 原操作返回 cancelled，旧宿主及清单恢复，socket 重新 enabled / active |
| enabled / active | 普通通道 EOF | broker 保留失败退出，旧宿主及清单恢复，socket 重新 enabled / active |

四项均确认 root worker 已退出，事务、暂存和目标目录临时文件已清理；没有用取消请求的确认替代原操作结果。顶层测试耗时 234.38 秒，各场景从撤销到恢复及检查约 20.8–23.6 秒，环境为 QEMU TCG，这些时间不作为产品性能指标。

不同版本使用有效宿主的不同 Go build ID，验证实际替换和旧文件恢复，不代表真实历史版本的数据迁移或物理断电。

## 检查与复现

- 管理模块普通单元 6 项通过，5 个环境/子进程 fixture 按各自前提跳过；上述四项在实际 VM 单独执行并通过。
- Linux 交叉编译、管理/安装 Go 静态检查、Go 格式和两份 shell 语法检查通过。
- 187 项原生与 QA 源码输入和构建快照一致，宿主、核心、测试二进制摘要、四份观察记录与原始日志见[证据索引](linux-broker-write-cancellation/evidence.json)。

```sh
# Linux QA 主机：完整管理、认证协议、真实替换取消及安装器边界测试。
bash tools/verify_linux_systemd_vm.sh --service-management
```

通用入口已加入新场景；本轮实际执行使用独立 Alpine/QEMU 包装脚本，只运行新增的四种替换取消场景。没有把前轮管理、认证和内部 checkpoint 结果计为本轮重新执行。

## 继续范围

公开 Linux `capabilities.tun` 继续保持 false。活动桌面的图形认证、设置页安装/卸载完整链路、其他桌面/发行版兼容与正式分发继续进行。macOS 宿主、iOS 网络扩展、Android 真机及全页面弹窗的 Figma 核对仍按[实现清单](../IMPLEMENTATION_STATUS.md)推进。上一轮 468 项 Flutter、108 张布局截图与预览包摘要保留其当时范围，本阶段没有新的 Flutter 或视觉执行。
