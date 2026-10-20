# macOS 核心与凭据基础接入

日期：2026-10-20。基于 `0f80987cac940518e77f23816c5490223debff76` 及保留的工作区修改。用户目前没有 Mac，要求继续推进可验证代码。本轮在 Windows 和隔离 WSL 进行检查；没有使用真实订阅、用户数据库、用户钥匙串或手机。

## 改动

- Go 宿主允许 macOS 使用共享的私有会话、本地代理、规则、链和遥测代码。Dart 状态协议接受 Intel / Apple Silicon 的本地端口能力，拒绝未接入的系统代理或 TUN 声明。macOS 系统代理、TUN、菜单栏、启动项与 iOS 仍未完成；公开 Linux TUN 仍为 false。
- 新增固定邻接路径的 `rainlink-keychain` Swift helper，使用 Security.framework 存取 32 字节主密钥，复用现有 AES-256-GCM 和记录身份认证。仅写入加密凭据时允许创建密钥，解密缺失时返回错误。并发创建使用 `SecItemAdd`，重复时回读，不覆盖已有密钥。
- Go 与 helper 通过有界私有 stdin/stdout JSON 通信。没有命令行密钥、`security -w` 调用或节点密码传入 helper；超时/取消终止子进程，私有输出缓冲清理，系统诊断不会进入公开错误。Linux 的有界输出实现提取为共用文件，行为不变。
- 新增 `tools/build_macos.py` 的 `prepare` / `bundle` 和 `tools/dev.sh` 接入。先核对未签名核心的源码锁，再本地 ad-hoc 签名，将签名后的 SHA-256 在链接时编入 Go 宿主。原始锁定核心不被修改，运行时不接受可写清单或环境变量覆盖摘要。helper 和宿主签名后装入 `.app/Contents/MacOS`，核心源码与许可证装入 Resources，外层签名保持已锁定的核心字节。
- 构建检查原生输入、Mach-O 架构及 Figma/字体/许可资源，文件被替换、过期输入或签名失败时拒绝继续。首发目标按开发方案为直接分发，macOS 最低版本设为 13.0；去掉模板 App Sandbox，Debug 保留 JIT entitlement，补上 CocoaPods 入口。App Store 沙箱渠道需要独立适配。

Swift helper、Xcode/CocoaPods 和 codesign 在本机均没有执行。Python 构建测试使用明确标注的编译器/签名 fixture，只证明流程与失败处理。当前没有生成或验收 macOS `.app`、DMG、Developer ID 签名或公证；不能据此宣称 macOS 软件已可运行。首轮 Mac 依赖解析还需生成并审查 `Podfile.lock`。

## 验证

| 检查 | 本轮结果 |
| --- | --- |
| Flutter 全量 | **474 项通过**，[原始事件](macos-foundation/flutter-tests.jsonl) |
| Flutter 分析与格式 | 无问题；284 个文件、格式无改动 |
| Windows Go | vet 通过；**126 个通过事件、27 个跳过事件**，[事件](macos-foundation/windows-go-tests.jsonl)；跳过项包含未显式启用的真实核心/权限场景 |
| Windows 真实核心回归 | **2 项通过**：锁定核心摘要与本机认证 HTTP 的实际转发、模式切换、字节计数和断开；独立临时状态，无系统代理接管，[事件](macos-foundation/windows-core-tests.jsonl) |
| Linux 凭据回归 | WSL 内实际执行 ELF，**59 个通过事件、2 个跳过事件**，覆盖有界真实进程、锁和取消；两项真实 Secret Service 测试明确跳过，[日志](macos-foundation/linux-securestore-tests.log) |
| Python 构建回归 | **23 项中 21 项通过、2 项 POSIX 文件测试在 Windows 跳过**；包含 8 项新增 Mac 流程 fixture，[日志](macos-foundation/python-tests.txt) |
| macOS 交叉编译 | Go 1.25.5；**arm64 / amd64 宿主、securestore/session/coreprocess 测试程序全部编译成功**，两架构 vet 通过，Mach-O CPU header 回读符合；未执行，[摘要与大小](macos-foundation/cross-compilation.json)、[arm64 构建元数据](macos-foundation/host-arm64-build-info.txt)、[amd64 元数据](macos-foundation/host-amd64-build-info.txt) |
| 核心锁 | 两架构均从固定 sing-box v1.12.25 源码构建，证书扩展测试在 Windows 执行通过；按新锁再次复核成功，[arm64](macos-foundation/core-arm64-build.json)、[amd64](macos-foundation/core-amd64-build.json) |
| 入口 | Bash 语法检查通过；entitlement plist 解析通过；Windows 原生 Mac 构建入口按预期拒绝，没有伪造产物 |
| Figma 图标 | Bridge 实时连接 RainLink，重新原生导出 **44 个 SVG，全部与运行资产逐字节一致**，[摘要](macos-foundation/figma-assets.json)、[导出文件](macos-foundation/figma/) |

通过事件包含 Go 子测试，不代表独立端到端场景数。汇总见 [checks.json](macos-foundation/checks.json)。本轮没有修改产品布局或图标，没有重新进行 Windows/Linux/Android 全页面渲染；上一阶段的 108 张布局及原生退出结果继续以其[封存报告](linux-flutter-lifecycle.md)为准。

macOS 原始核心为 `1.12.25-rainlink.1`：

- arm64：`18269e2b48ba8e1f3119af7b42b1827ca0348aa06b342cbbe0e9a53762e8b8e9`
- amd64：`3fc3cb6443b82e5bc115e57228544dc461ca6e01f5567c28a4b3a24d5d45b35f`

现有 Windows/Linux 核心锁定摘要未变，旧预览包、用户配置和历史报告未覆盖。macOS 交叉编译程序保存在 `build/host/darwin-arm64` / `build/host/darwin-amd64`；它们不是 macOS 成品软件。

## Mac 可用后的入口

Mac 需 macOS 13+、Xcode/命令行工具、CocoaPods、Python 3.10+、Go 1.25.5 和 Flutter 3.29.3。在仓库根目录执行：

```sh
bash tools/dev.sh check
bash tools/dev.sh run
bash tools/dev.sh build
```

`run` / `smoke` 先准备固定核心、原生 helper 和宿主；`build` 尝试原生 Release 构建、装入运行文件并重新本地签名，输出验证结果到 `build/macos/<架构>/`。`package` 仍明确拒绝，正式 DMG/签名/公证尚未实现。这些入口已完成跨平台流程回归，仍需要 Mac 原生执行才能验收。

先在独立 macOS QA 登录用户中验证钥匙串首次创建、再次启动、并发创建、允许/拒绝/取消、锁定与缺失密钥、同记录认证及凭据重导入；固定产品 service 不提供任意修改/删除用户钥匙串的选项。再验证真实本机核心节点/链/规则、端口与遥测、EOF/强杀恢复、系统保存器及 UI。ad-hoc 重新编译可能触发新的钥匙串授权，正式签名的稳定访问要求仍待处理。系统代理须按实际网络服务保留/恢复并验证后来修改者，完成之前继续关闭其能力。

完整五平台目标保持进行中。代码未自动提交、推送或发布。本轮证据摘要见 [evidence.json](macos-foundation/evidence.json)。
