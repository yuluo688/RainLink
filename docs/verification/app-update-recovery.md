# Windows 更新中断恢复验收 · 2026-10-17

本轮交付 **0.1.0+3 开发预览**，补齐更新事务持久记录、下次启动自动恢复和独立启动入口。实际验收包含强制结束测试 updater；没有执行物理断电测试。上轮正常更新、双端更新页面和下载行为的记录保留在 [应用更新验收](app-updates.md)。

## 启动与更新

完整目录现在使用 schema 2：`rainlink.exe` 为不依赖 Flutter DLL 的 Go 启动器，`rainlink-ui.exe` 为 Flutter 主程序。日常双击 `rainlink.exe`，开机启动同样使用该入口。启动器使用明确的原生资源标识，避免开发目录残留的旧 `rainlink.exe` 被误用为开机启动入口。

启动器在替换过程中始终保留。在线更新要求启动器的大小与 SHA-256 不变；需要改变启动器或从 schema 1 迁移时，必须关闭 RainLink，将完整新包解压到新目录后使用。后续在线包需复用同一启动器。当前是本地预览，没有将旧包原位升级为新布局，也没有发布 GitHub Release。

启动器、更新器和恢复程序通过按规范化安装路径区分的 Windows Global mutex 串行操作。锁不会在安装目录创建文件；更新器被强制结束后由系统释放。回滚重启启动器时有限等待锁释放，避免与 helper 退出竞争。恢复前按真实可执行文件路径打开并等待 GUI 进程句柄，不依靠 PID 名称批量关闭进程。`--repair` 仅恢复、不启动界面；GUI 仍在运行时返回 busy，不报告完成。

安装根目录的 `.rainlink-update.json` 记录目标、暂存位置、令牌、前后 manifest、阶段及 SQLite/WAL/SHM/journal 的大小与摘要。状态先写临时文件、Sync，再通过 Windows MoveFileEx 发布；日志不随 staging 提前删除。恢复读取磁盘实际位置，核对摘要后逆向处理已发生的移动，恢复本身再次中断也能继续。取消或验证失败保留可恢复材料。

SQLite 备份完整通过校验后才恢复，以临时复制和替换逐一还原，不提前删除唯一备份。候选确认前由 Windows Job 管理，强杀 helper 会结束尚未确认的候选及其继承子进程。持久 accepted 阶段为提交点：提交以后保留新程序与迁移后的数据，最终握手或清理失败也不降级数据库。只有完成阶段持久落盘，才删除该事务拥有的备份和暂存目录。

## 验证

| 检查 | 结果及证据 |
| --- | --- |
| Dart 格式、静态分析、全量 Flutter | **332 项通过**、分析无问题；`app/build/recovery-full-check.log` |
| Go vet / 全量测试 | **79 个通过测试事件、26 个跳过、0 失败**；跳过的环境保护项不计为通过；`build/recovery-go-tests.jsonl` |
| 持久恢复回归 | 每次运行文件移动后模拟中断、恢复过程中再次中断、清理中断、备份损坏、路径/身份篡改、取消、Windows 文件名大小写及提交后握手失败 |
| 真实强杀 helper | 提交前实际候选进程被系统结束、旧程序/数据库恢复；提交后 helper 被杀，候选保留，恢复不降级数据；实际启动器重开通过；`native/host/internal/update/recovery_windows_test.go` |
| Windows Flutter 原生集成 | loopback 下载、实际 SHA-256、复制真实 helper、准备及取消通过；[windows-evidence.json](app-update-recovery/windows-evidence.json) |
| 实际 Flutter AOT 安装 | 真实 schema 6 初始化、首帧确认、持续可见、正常退出通过 |
| 实际 Flutter AOT 失败回滚 | schema 5 数据迁移后遇损坏偏好，恢复旧程序与 schema 5 数据字节，旧程序经启动器重启通过 |
| 实际 Flutter AOT 中断恢复 | 准备完成后真实强杀 helper，关闭原窗口，双击入口自动清理事务并重新显示实际 AOT 窗口通过 |
| Python 打包回归 | **5 项通过**，覆盖摘要、必需 UI/启动器/更新器、错误引擎及原生版本、本地数据与运行中事务文件拒绝 |
| 独立启动器 | 在只有 `rainlink.exe`、没有 Flutter DLL 的目录执行 repair 成功；不创建锁文件；[launcher-evidence.json](app-update-recovery/launcher-evidence.json) |

实际 AOT 三种场景见 [actual-release-update-evidence.json](app-update-recovery/actual-release-update-evidence.json)。脚本只修改复制 UI 的 CompanyName，把 path_provider 指向新建 QA 配置，并使用不联网、不修改代理的 fixture 宿主。它证明实际 Dart/Flutter 启动与数据恢复，不代表在真实机场连接中完成线上更新。QA 配置保留供审计，不递归删除外部配置。

新增中断恢复的首次截图检查遇到尚未显示的初始 Win32 窗口，已修正为等待窗口可见后重跑，最终三种场景通过。首轮原生构建还暴露了旧 CMake 缓存目标名，已接入缓存默认值迁移；以上失败未计入通过结果。

## 界面与图标

从当前 RainLink Figma 文件重新导出品牌、刷新、下载、向下与返回 5 个 SVG，与运行资源和最终 ZIP 内资源逐字节一致，见 [icon-verification.json](app-update-recovery/icon-verification.json)。重新读取桌面更新分类 `59:47288` 和移动分类 `59:48458`，参考截图为 `reference/recovery-*-updates-live.png`。

27 个原生 PNG 与 9 尺寸 ICO 按原 Figma 品牌 PNG 重新生成校验通过；检查使用符合 `tools/requirements-design.txt` 的捆绑 Python/Pillow。启动器复制 UI 的全部图标资源，9 个图像载荷与原 ICO 一致，明确的启动器标识和版本资源也已回读。重复嵌入资源的二进制摘要相同。启动器自身版本为 1.0.0.0，产品 UI、设置和宽窗口侧栏显示实际应用版本 0.1.0+3。

实际紧凑概览、更新分类与宽窗口已检查，截图在 `app-update-recovery/release-*.png`。本轮没有改动移动布局；前轮 56 张双端深浅主题更新状态 fixture 保留在 `app-updates/`，没有计为本轮重新生成的截图。没有宣称所有页面逐像素一致，也没有把 Windows 移动布局测试当作移动平台原生验收。

## 本地包与数据

新包为 `build/RainLink-windows-x64-recovery-preview.zip`，对应标准资产 `build/RainLink-0.1.0+3-windows-x64.zip`。两者均为 **46,810,871 字节、78 项**，SHA-256：

```text
c96ce55968ad57441359484e461d1ece98c2f563cbe2135c8ad89d0f9564fff9
```

打包核对 SDK Release 引擎、固定核心、当前宿主/更新器/启动器、每个运行文件及 ZIP 摘要，包含许可和核心源码，不含用户数据库。构建信息为 [app-update-recovery-build.json](app-update-recovery-build.json)，最新入口为 [desktop-build.json](desktop-build.json)。旧 0.1.0+2 两个包保留原摘要。

本机真实 Release 由启动器打开。2026-10-17 05:36:50 点击生产源检查，返回“尚无可用发布版本”，没有下载或安装外部包。用户配置前后保持 schema 6、68 个节点、1 个分组、0 个覆盖、4 个偏好；数据库表、开机启动项和系统代理摘要全部一致。自动连接、订阅维护、自动检查与到期提醒均未开启。正常退出后无 RainLink、宿主、核心或 updater 残留；原有 FlClashHelperService PID 6156 保留。证据见 [release-evidence.json](app-update-recovery/release-evidence.json)。

物理断电、正式在线发布、签名安装/卸载、启动器在线替换、标准用户实际 Program Files/UAC、多用户与其他平台服务仍未完成。全产品状态以 [实现清单](../IMPLEMENTATION_STATUS.md) 为准。

复现时串行运行 Flutter 单测、Windows 集成与 Release 构建，避免共享引擎目录被覆盖：

```powershell
./tools/dev.ps1 check -FlutterRoot '<Flutter SDK>'
./tools/dev.ps1 prepare
# app 目录：flutter test integration_test/windows_app_updates_test.dart -d windows
./tools/dev.ps1 build -FlutterRoot '<Flutter SDK>'
python tools/verify_app_updates.py
python tools/package_windows.py --label recovery-preview --flutter-root '<Flutter SDK>'
python tools/package_windows.py --release-asset --flutter-root '<Flutter SDK>'
```
