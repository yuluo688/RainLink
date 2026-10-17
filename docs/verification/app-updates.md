# Windows 应用更新验收 · 2026-10-17

Windows「设置 → 更新」已接入版本检查、渠道选择、可取消下载、SHA-256 校验和确认安装。当前为 **0.1.0+2 开发预览**；自动检查默认关闭，只在应用启动时按偏好执行，不自动下载或安装。其余平台保留明确的未接入状态。

本文保留 0.1.0+2 当时的结果。最新 0.1.0+3 已接入持久事务日志、独立启动器及强杀更新器后的恢复，新增验收与包见[中断恢复验收](app-update-recovery.md)。

## 发布源与使用

生产发布源固定为 `https://api.github.com/repos/yuluo688/RainLink/releases?per_page=100`，最多读取 100 个版本和 4 MiB 元数据。稳定渠道排除预览版；数字构建号参与版本比较。网络错误、限流、格式错误与空发布列表分别呈现，空列表不显示“已是最新版本”。

发布资产必须命名为 `RainLink-<完整版本>-windows-x64.zip`，去掉 tag 的前导 v，保留 +build，例如 `RainLink-0.1.0+2-windows-x64.zip`。仅接受该仓库的精确下载 URL 及 GitHub 资产 CDN 的 HTTPS 跳转；GitHub 资产缺少 `sha256:` 摘要时禁用下载。下载先保存临时文件，再核对大小与摘要，取消或失败关闭网络及文件后清理；压缩包最大 300 MiB。旧下载缓存保留最近两个目录，超过七天清理。

点击「安装并重启」先显示确认框。确认后准备并验证包，不替换正在运行的应用；原应用先恢复网络、暂停后台任务、等待偏好落盘及宿主关闭，再提交安装并退出。如果断开或交接失败，原窗口恢复可操作状态并保留错误。

本轮用最终 Release 点击「检查更新」，成功访问生产源，显示“尚无可用发布版本”，上次检查为本机 2026-10-17 05:01:32。没有创建或发布 GitHub Release，因此没有声称完成正式线上下载升级。

## 安装事务与恢复范围

随包分发 `rainlink-updater.exe` 和 `rainlink-bundle.json`。manifest 记录产品、平台、版本及每个文件的大小和 SHA-256；原应用先核对 helper 摘要，helper 重新核对压缩包、manifest 及所有解压文件。路径校验拒绝穿越、绝对路径、ADS、设备名、大小写重名、符号链接、reparse point 和文件/目录冲突。展开上限为 1 GiB、4096 项。Flutter 必需的根文件 `native_assets.yaml` 在明确允许列表内。

helper 使用验证过的原进程路径和保留的 Windows 进程句柄等待退出，避免 PID 复用。准备、提交、取消通过有界私有 stdio 消息握手；原进程还活着时不会替换文件，也不会由 helper 强制关闭。staging 与安装目录位于同一卷，只有 manifest 管理的根项参与替换，其他根文件保留。

原应用退出后，备份 SQLite 及 WAL/SHM/journal，再替换程序。候选版本必须完成数据库与偏好初始化、窗口和首帧渲染，并与 helper 确认；确认之前不启动核心、自动连接、订阅维护或通知。替换失败或候选启动失败时，先确认候选进程退出，再恢复程序和数据库，重启旧程序。无法确认停止或恢复失败会保留备份及 `recovery-required` 回执，不报告成功。

当前覆盖正常进程执行中的失败。**断电或强制结束 updater 后的持久事务日志和自动恢复尚未实现**；Windows 程序签名、安装/卸载、安装目录迁移和更新当前用户开机启动路径仍属于后续分发范围。旧预览包没有 manifest，需要先手动替换完整目录才能使用后续在线更新。

## 验证结果

| 检查 | 证据与结果 |
| --- | --- |
| Dart 格式、静态分析 | 通过，分析无问题 |
| Flutter 全量 | 329 项通过；`app/build/updates-full-flutter-final.log` |
| Go vet / 全量测试 | 51 个测试事件通过、26 个环境开关保护的测试跳过、0 失败；未把跳过项算作通过 |
| Windows 真进程 helper | 安装、启动失败回滚、准备取消、错误父进程拒绝通过；`native/host/internal/update/process_windows_test.go` |
| Flutter 原生下载/准备 | loopback HTTP → 实际 SHA-256 下载 → 复制真实 helper → ready → abort → 清理通过；[windows-evidence.json](app-updates/windows-evidence.json) |
| 实际 Flutter AOT 正常更新 | helper 安装隔离副本，真实 schema 6 初始化、首帧确认、窗口保持及正常退出通过 |
| 实际 Flutter AOT 失败回滚 | schema 5 迁移后遇损坏偏好，候选退出；恢复旧程序、schema 5 及数据库字节摘要，旧程序重新启动通过 |
| Python 3.8 打包回归 | 4 项通过，覆盖流式摘要、必需运行文件、原生资产、敏感本地数据拒绝及混入错误引擎/宿主/核心拒绝 |
| Windows Release 实窗 | 紧凑概览、更新详情和实际生产源检查通过；正常退出后无 RainLink / 宿主 / 核心 / updater 残留 |

实际 AOT 更新脚本为 `tools/verify_app_updates.py`。它只修改复制 EXE 的 CompanyName，将 path_provider 路由到全新的 QA 配置；复制包使用不会联网、不会修改代理、只返回 idle 的测试宿主。生产二进制和用户 RainLink 配置不参与替换。此测试证明真实 Dart/Flutter 启动确认与数据库回滚，不代表在真实用户连接中完成了线上升级；会话关闭顺序由组件回归覆盖。

实际证据为 [actual-release-update-evidence.json](app-updates/actual-release-update-evidence.json)。首次验证中测试宿主不能响应断开，之后补齐了离线协议；另一轮因 Python SQLite 连接未关闭而阻止恢复，已修正为显式关闭，再次验证通过。这些失败未计为通过。

自动审批拒绝了首次残留目录的递归删除，未提供具体理由，因此保留 `build/rainlink-update-release-toeodp6q`；测试进程已关闭。验证脚本现保留新建的 `qa*` 配置用于本地审计，不递归删除外部配置目录。这些数据均为隔离 fixture，不是用户订阅。

## Figma 与双端布局

实时参考为桌面更新分类 `59:47288`、移动更新分类 `59:48458`、桌面有更新态 `59:45613`。截图位于 `reference/desktop-updates-live.png`、`reference/mobile-updates-live.png` 和 `reference/desktop-updates-available-live.png`。

保留两张卡片、薄荷强调色、六分类导航、移动左上返回和移动整行操作；运行时显示实际版本、网络状态与新增的下载/安装状态。布局使用已有公共组件，适配 1440×900、960×640、393×852 和 320×640 大字，深浅主题、7 种更新状态共 **56 张 fixture 截图**通过。手机截图在 Windows 测试 runner 中使用移动布局和安全区，不能作为 iOS/Android 原生更新验收。

逐一重新导出并核对 refresh、download、chevron_down、back 和品牌标记，5 个 SVG 与运行资源字节一致；[icon-verification.json](app-updates/icon-verification.json)。人工抽查了桌面深浅主题、手机可下载态、小屏大字未接入态及实际 Release。宽窗口侧栏的版本也改为读取生成的构建信息，实窗确认与更新页同为 0.1.0+2。结构与资源对应设计；实际版本、默认开关、辅助文案、状态操作数量和可访问点击高度有业务差异，没有宣称截图逐像素一致。

## 本地交付与用户数据

预览包为 `build/RainLink-windows-x64-updates-preview.zip`，**44,006,216 字节、77 项**。同内容的标准资产为 `build/RainLink-0.1.0+2-windows-x64.zip`，两者 SHA-256 均为 `b836364ab774f166482907d1be27cd6b8601193c4e2fa65a9b15913dc940cc18`。这是本地包，未发布。

打包工具验证 SDK Release 引擎、固定核心、本次宿主和 updater，核对 ZIP CRC 和全部 manifest 文件摘要，包含许可及核心源码，不含用户数据库。元数据为 [app-updates-build.json](app-updates-build.json)，最新入口为 [desktop-build.json](desktop-build.json)。旧包和其验收记录保留。

真实 Release 启动前后，schema 6、节点 68、分组 1、覆盖 0、偏好 4，数据库表、开机启动和系统代理摘要全部一致。未打开自动检查、自动连接、订阅更新或提醒。原有 FlClashHelperService PID 6156 保留；未启动或修改 FlClash。摘要见 [release-evidence.json](app-updates/release-evidence.json)。

复现本地构建及打包：

```powershell
./tools/dev.ps1 check -FlutterRoot '<Flutter SDK>'
./tools/dev.ps1 build -FlutterRoot '<Flutter SDK>'
python tools/package_windows.py --flutter-root '<Flutter SDK>'
python tools/package_windows.py --release-asset --flutter-root '<Flutter SDK>'
# 关闭其他 RainLink 窗口后，运行隔离 AOT 更新验证；保留 QA 配置供审计。
python tools/verify_app_updates.py
```

Flutter 单元测试、Windows 原生集成、视觉集成和 Release 构建必须串行运行，防止 Flutter 共享引擎目录在构建期间被覆盖。
