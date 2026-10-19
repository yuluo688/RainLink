# Linux 服务管理与安全退出续验

后续已补充等待认证时取消的实现与真实 polkit 协议验证，见[等待认证取消](linux-service-authentication-cancellation.md)。本页及 evidence.json 保持此前五场景和共享退出的快照，不随后续源码改变。

2026-10-20。继续补齐 Linux 功能，完整五平台目标保持进行中。本轮未操作用户真实订阅、数据库、FlClash 或手机。前一检查点 `ff17b10` 的首次下载失败及当时测试结果保留在[阶段记录](linux-tun-service-management.md)。

## 已完成的实现

Linux 和 macOS 现在接入桌面窗口的安全退出流程；原先该流程只在 Windows 启用。退出会等待权限服务操作取消并结束，包括操作后的状态回读，再恢复网络连接、等待偏好写入并关闭宿主。退出失败会恢复管理入口、显示窗口并允许重试。没有托盘适配器时，旧的“关闭到托盘”偏好不会让窗口无法退出。此处 macOS 只有共享流程的组件验证，不代表 macOS 原生网络服务已完成。

权限服务控制器增加退出时的暂停与恢复，暂停后不接受新管理操作。确认框限制内容宽度，安装、卸载和恢复文案改为用户可理解的说明，避免在紧凑窗口中铺成一整行。

QA 入口增加固定摘要的 `pkexec` 离线种子，guest 再与签名 Debian apt 索引核对后安装。测试还使用不同构建元数据的有效宿主，验证实际文件替换和已禁用 socket 状态保持。此构建变体用于验证安装管理，不模拟真实旧版数据库或协议迁移。

## 实际 systemd / pkexec 验证

普通 UID 65534 的客户端通过生产 `manage-tun-service` → 真正 `pkexec` → root worker 完成下列场景，实际 Debian VM 的顶层测试用时 180.71 秒：

| 场景 | 已观察结果 |
| --- | --- |
| 拒绝授权 | 返回授权错误，服务仍为 missing |
| 允许授权 | 安装后 current / enabled / active，恢复和重复安装保持一致，卸载后 missing |
| 版本替换 | different → current；原先 disabled / inactive 的 socket 在更新、恢复、重复安装后仍保持禁用与未启动 |
| 取消操作 | root 控制端持有真实安装锁，观察到已授权 root worker 打开该锁后才允许普通用户取消；先确认请求，再收到原安装的 cancelled 错误；root worker 在锁释放前退出，没有遗留安装数据 |
| 管道 EOF | 同样在真实安装锁等待点关闭普通管理通道；取消错误没有被吞掉，root worker 在锁释放前退出 |

取消与 EOF 场景证明的是**授权完成后、安装事务写入前**的实际进程取消。它们不证明桌面认证弹窗中点击取消、事务写入过程中取消、真实桌面退出或断电的全部恢复行为。polkit 规则只在测试 VM 内按固定 UID / action / 程序放行或拒绝，没有在宿主配置规则，也没有验证密码输入。

环境为 Windows 上的私有 WSL mount / PID namespace、临时 Alpine 3.22.2 / QEMU 10 TCG，以及 Debian 13 / Linux 6.12.113 / systemd 257 / polkitd 126。Debian 使用前阶段安装验收的只读基底加新 overlay；没有共享宿主凭据、设备、目录或入站端口给 guest。实际运行使用本地隔离包装脚本，通用 `tools/verify_linux_systemd_vm.sh --service-management` 的下载检查和语法单独检查，本轮没有在完整 Linux QA 主机上直接执行整份通用脚本。

## Flutter、界面与图标

- Flutter 全量 **460 项通过**，machine 最终 `success:true`、退出码 0；静态分析无问题，相关 Dart 文件格式检查通过。
- 服务、退出和桌面集成重点 **23 项通过**：等待原操作和回读、退出拒绝后恢复管理、Linux/macOS 无托盘适配器时退出、Windows 托盘及更新退出流程。
- Linux 管理单元 5 项通过；真实 VM 场景默认跳过，不混入单元测试通过数量。新增 Linux 文件检查测试沿用前轮已通过结果；生产 Go 代码本轮未改动。
- 新增 **40 张**原生 Flutter fixture 截图，覆盖 1440×900、960×640、深浅主题、五种服务状态、确认、等待授权、取消等待与取消结果。运行于 Windows runner，注入 Linux 布局和服务 fixture；不是 Linux GUI 实机或真实系统授权窗口。
- 当前 **44 个 SVG**（图标、国旗和品牌）与仓库保存的 2026-10-17 Figma 原生导出逐字节一致。新卡片复用 shield / refresh 图标、主题、卡片和按钮；本轮查看了核心页参考和实际渲染，修复过宽确认框。Bridge 当前未连接，不将旧导出核对等同于最新设计稿核对，也不声明全页面已达到像素一致。

截图和回执位于 [linux-service-management](linux-service-management/)，摘要与来源见 [evidence.json](linux-service-management/evidence.json)。该快照包含当时源码与产物摘要；后续修改需要产生新证据，不能沿用为新源码的证明。失败运行保留在忽略的 `build/qa/linux-manage/vm/` 与 `vm-management-20261020-01/`；首次实际管理闭环与扩展续验分别在 `vm-management-20261020-02/`、`vm-management-20261020-03/`，没有把失败运行改写为成功。

## 继续完成的范围

Linux 公开 `capabilities.tun` 仍为 false，已通过实际 Linux 宿主状态输出回读确认。下一步为活动桌面认证/取消弹窗、事务写入期间取消、Linux GUI 实机、打包与生命周期续验；macOS 原生宿主、iOS 网络扩展、Android 真机及双端全页面/弹窗与最新 Figma 的核对仍按[实现清单](../IMPLEMENTATION_STATUS.md)推进。
