# Linux 权限服务管理阶段记录

日期：2026-10-20。此提交保存服务管理实现及自动化验证进展，不代表 Linux TUN 或五平台产品已完成。前阶段安装、权限日志和 2026-10-17 收尾记录保留原结果及摘要，不作为本次源码的摘要证明。

## 已实现

- Linux「设置 → 核心引擎」显示权限服务状态，提供安装/更新、卸载、恢复、刷新、取消及确认弹窗；其他平台隐藏入口，复用现有主题与 Figma SVG。
- 独立管理进程只允许固定动作和空参数，拒绝任意路径、命令、重复字段及重复 ID；普通用户经固定 `pkexec` 调用 root worker，不由应用读取密码。
- 管理前要求会话已断开；管理期间阻止新连接。取消确认后继续等待原操作结束，完成/失败后回读状态，拒绝虚假安装成功。
- 文件状态检查只读，使用 root 目录与文件描述符验证固定安装文件及当前发行内容。未知状态不推断服务未启动。
- 增加普通用户 broker 经真实 pkexec/polkit 的 VM 测试及 `tools/verify_linux_systemd_vm.sh --service-management` 入口，覆盖拒绝、安装、恢复、重复安装和卸载；该真实测试本轮尚未执行完成。

## 已验证

| 检查 | 结果与范围 |
| --- | --- |
| Flutter 全量测试 | 454 个非隐藏测试通过，machine 最终 `success:true`，退出码 0；在最后一次 UI 修正之前执行 |
| 最后 UI 修正回归 | `tun_service_ui_test.dart` 6 项通过，含未知状态、其他平台隐藏、深浅主题、320/640 宽及 1.5 倍字号 |
| Flutter 静态分析与格式 | `No issues found`；相关 Dart 文件已格式化 |
| Linux 管理单元 | 5 项通过；真实 systemd/普通用户 fixture 默认跳过，不计为授权测试成功 |
| Linux 文件状态检查 | 缺失、匹配、不同版本、部分缺失、符号链接拒绝及只读保持测试通过 |
| Go 静态与编译 | 新代码 `gofmt` 检查、Linux 管理/安装 `go vet`、Linux amd64 测试及宿主交叉编译通过 |
| Windows 回归 | 宿主入口编译及 cli/session/coreprocess 测试通过，未启用真实系统代理测试开关 |

## 真实管理 VM 未完成

独立 Debian VM 正常启动，`apt-get` 安装缺失的 `pkexec` 时，从 Debian 镜像下载 `pkexec_126-2_amd64.deb` 遭遇 TLS 连接重置，guest 在测试开始前退出。提取器随后因没有 JSON 结果中止；这不是管理测试通过或授权路径失败的证据。VM 内没有生成 `real-systemd-management-tests.log`，不得用前阶段的 root 安装或权限日志 YES/NO 结果代替本次普通用户管理验收。

本机原始证据位于忽略的 `build/qa/linux-manage/`：`flutter-tests.jsonl`、native 单元日志，以及 `vm/systemd-results-1792426565/apt-install.log`、`cloud-output.log` 和 `vm/vm-serial.log`。这些本地产物未加入 Git，也未修改用户真实数据库、订阅或凭据。

## 复现与后续

```sh
# Linux QA 主机，需要脚本列出的工具、锁定镜像及旁置核心。
bash tools/verify_linux_systemd_vm.sh --service-management

# 管理单元测试不请求授权；真实系统测试默认跳过。
cd native/host
go test ./internal/linuxmanage ./internal/linuxinstall
go vet ./internal/linuxmanage ./internal/linuxinstall
```

```sh
cd app
flutter test --no-pub
flutter analyze --no-pub
```

下一步恢复 VM 依赖下载并验收普通用户真实管理闭环，再验证活动桌面认证/取消弹窗、取消或退出后的实际恢复、Linux GUI 渲染与 Figma、发行版打包和生命周期。当前仅有组件布局测试，未完成本轮 Linux GUI 实机视觉核对；未更新预览安装包，Linux 公开 `capabilities.tun` 继续为 false。
