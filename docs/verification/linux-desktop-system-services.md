# Linux 通用设置、托盘与通知

日期：2026-10-20。基于 `0f80987cac940518e77f23816c5490223debff76` 与未提交修改，延续[活动桌面授权](linux-graphical-service-management.md)。五平台开发目标仍在进行，公开 Linux `capabilities.tun` 保持 `false`。

## 本轮实现

Linux 的「设置 → 通用」现在接入当前用户的自动启动、StatusNotifier 托盘和系统通知。复用原页面和共享偏好；Windows 保留原有通道兼容与托盘通知依赖，Linux 通知可以独立于托盘运行。服务缺失时说明原因，并提供重新检查。

原生实现使用 GTK/GIO，未新增产品运行依赖。会话总线请求异步执行，单次调用限时 900 ms，销毁时取消。托盘通过独立总线名称注册与注销，面板消失时恢复隐藏窗口，面板重启后按保存的偏好重新注册。通知只传递订阅数量，不包含订阅名称、地址或认证信息；点击到期通知进入分组。

自动启动写入当前用户 XDG 配置目录下的 `autostart/dev.rainlink.rainlink.desktop`，只处理属于当前安装的条目。其他安装、损坏文件、超限文件和符号链接保留；新条目完整写入私有临时文件后发布，已有自有条目按 etag 替换。

## 发现并修复

- 路径含百分号时，GIO 会在展开 `%%` 之前检查首个可执行文件。启动项现在使用固定 `/usr/bin/env --` 加引号参数，直接执行应用；实际系统启动器已解析并执行包含空格、百分号、引号、反引号、美元符号和反斜杠的测试路径，收到 `--autostart`。
- 快速开启再关闭托盘时，尚未完成的总线探测可能重新注册图标。增加请求代次校验，较早的开启操作返回取消；[修复前失败](linux-desktop-system-services/native-before-fix.log)和[修复后回归](linux-desktop-system-services/native-tests.log)分别保留。
- Linux 已保存「关闭托盘、保留通知」后，启动入口仍按 Windows 的依赖校验，可能进入启动失败页面。现在按 Linux 的独立通知能力校验；新的实际 Release 包通过保存、退出、重开和再次读取偏好验证。

## 实际验证环境

隔离 Debian 13 chroot，私有 mount/PID/network namespace，普通 UID 1000，Xvfb/Openbox、独立 D-Bus、QA 密钥环、真实 Xfce4 panel 4.20.4 与 Dunst 1.12.2。测试没有使用用户数据库、真实订阅或节点凭据，没有操作 FlClash、手机或宿主桌面设置。

测试依赖的 30 个发行版软件包共 3,061,844 bytes，按索引 SHA-256 校验后安装；见[输入清单](linux-desktop-system-services/desktop-stage-package-inputs.json)、[安装日志](linux-desktop-system-services/desktop-stage-dpkg-install.log)及[最终包审计](linux-desktop-system-services/desktop-stage-dpkg-audit.log)。中文通知使用 QA 用户字体目录中的现有 Noto Sans SC，未修改产品字体资产。

| 检查 | 实际结果 |
| --- | --- |
| Flutter 单元与组件回归 | **473 项通过**；[完整日志](linux-desktop-system-services/flutter-unit-tests.log) |
| Dart 格式与静态分析 | **283 个文件无格式改动，分析无问题**；[格式](linux-desktop-system-services/flutter-format.log)、[分析](linux-desktop-system-services/flutter-analyze.log) |
| 原生自动启动 | **4 项通过**：真实解析与启动、其他安装保留、外部文件与符号链接保留、禁用项重启用及移除；[日志](linux-desktop-system-services/desktop-autostart-test.log) |
| 原生 D-Bus 生命周期 | **3 项通过**：取消较早注册、注销后名称与 watcher 条目消失、20 次挂起请求期间销毁；[日志](linux-desktop-system-services/native-tests.log) |
| 无会话总线 | **1 项通过**：能力回读不可用，拒绝注册，不启动临时总线；[日志](linux-desktop-system-services/native-no-bus.log) |
| 真实 Flutter Linux 集成 | **1 项完整流程通过**：界面开关自动启动与文件回读、托盘唤回、Dunst 实际显示与默认动作、面板消失恢复窗口、面板重启自动注册、无托盘继续显示通知；[日志](linux-desktop-system-services/integration-visual-final.log)、[结果](linux-desktop-system-services/native-integration.json) |
| 最终源码一致性 | **745 项输入一致**；[输入摘要](linux-desktop-system-services/source-inputs.json)、[校验结果](linux-desktop-system-services/source-verification.json) |
| 完整 Release 包 | **77 个归档项、55 个运行资产、权限与逐文件摘要通过**；[打包结果](linux-desktop-system-services/package.json) |
| 解压后实际启动与重开 | 含空格路径下运行，保存独立通知偏好，重开后偏好相同，两次窗口退出均为 **0**；[运行结果](linux-desktop-system-services/release-runtime.json) |

原生 fixture 使用 `clang++ -std=c++14 -Wall -Wextra -Werror` 实际编译；完整 Flutter Debug/Release runner 也已编译。早期测试脚本遗漏窗口守卫和面板重启顺序的问题已修正；最终脚本用固定窗口 ID 的 `xwininfo` 验证映射状态，避免在面板销毁时扫描整个 X11 窗口树产生 `BadWindow`。最终源码与成功执行的脚本一致。

复现入口：[原生自动启动 fixture](../../tools/fixtures/linux_desktop_autostart_test.cc)、[原生总线 fixture](../../tools/fixtures/linux_desktop_integration_test.cc)、[实际 Flutter 集成](../../app/integration_test/linux_desktop_integration_test.dart)。Flutter 流程要求启动前设置独立的 `XDG_CONFIG_HOME=/tmp/rainlink-desktop-integration-<标识>/config`，在同一会话运行真实面板和 Dunst，并传入 `RAINLINK_TEST_DESKTOP=isolated`、`RAINLINK_VISUAL_OUTPUT` 与 QA `RAINLINK_HOST_PATH` 三个 dart-define。[本轮 Release 操作脚本](linux-desktop-system-services/desktop_release_stage.py)保存了空间路径解压、真实界面点击、偏好读取、退出和重开过程；它使用隔离环境专用路径。[退出前进程记录](linux-desktop-system-services/namespace-before-exit.log)只剩 namespace shell 与检查进程，随后 root shell 及整个 namespace 正常退出。

## Figma 与实际画面

当前 Bridge 文件为 `unsaved-mvfj9942-5y6aivnm` / RainLink，设置参考节点为 `2:19743`。**44 个 SVG 已重新原生导出，与当前应用资产逐字节一致**；[摘要记录](linux-desktop-system-services/figma-assets.json)。本轮没有重新生成或替换产品图标。

已实际检查 1440×900 深浅主题通用设置，以及 Release 默认 960×640 紧凑概览。设置保留 Figma 的双列分类、卡片、开关与薄荷色状态，显示实际版本和能力；额外的外观入口、平台说明及通知默认关闭属于运行行为差异，不能据此宣称全页面逐像素一致。移动端本轮只经过共享组件回归，没有重新进行 Android/iOS 原生验收。

- [当前 Figma 设置参考](linux-desktop-system-services/figma-desktop-general.png)
- [Linux 深色设置](linux-desktop-system-services/general-dark-panel.png)、[浅色设置](linux-desktop-system-services/general-light-panel.png)、[缺少托盘服务](linux-desktop-system-services/general-no-panel.png)
- [真实系统通知与 Figma 同源图标](linux-desktop-system-services/system-notifications.png)
- [Release 默认紧凑概览](linux-desktop-system-services/release-initial-compact.png)
- [Release 自动启动开启](linux-desktop-system-services/release-autostart-enabled.png)
- [关闭托盘、保留通知](linux-desktop-system-services/release-independent-notifications.png)、[重开后的通用设置](linux-desktop-system-services/release-general-reopened.png)

## 本轮产物与边界

`build/RainLink-linux-x64-preview.tar.xz` 已更新为本轮通过实际启动和重开的 **0.1.0+4** 包，同内容副本为 `build/RainLink-linux-x64-desktop-services.tar.xz`。

- 大小：**32,237,392 bytes**。
- SHA-256：`dbd9e195d92842d0bdb8134f8d75b27bc1b03054aacf5b88b44fb4796749659d`。
- 宿主 SHA-256：`3c94988871e41f58fcfa486b7c58ce749b1b2cac6a217ffa9c1cf586f46394e4`，沿用前阶段已构建宿主，本轮没有 Go 修改或新增 Go 执行。
- 前阶段 `aaea75ee…` 包另保留为 `build/RainLink-linux-x64-graphical-management.tar.xz`；历史报告与其测试范围保持原样。

实际 Release 仍有 GTK/Flutter 诊断，包括 `atk_socket_embed`、`FlutterEngineRemoveView`、`g_object_weak_unref`、无 engine 的 messenger；首次退出还记录到鼠标光标处理器的失效对象诊断。[首次运行日志](linux-desktop-system-services/release-launch-1.log)与[重开日志](linux-desktop-system-services/release-launch-2.log)完整保留，没有屏蔽输出。退出码 0 只证明本次正常退出，不代表这些生命周期问题已解决。

完整 GNOME/Plasma/Wayland、其他发行版、真实注销再登录自动启动、切网/休眠与正式分发仍待验收。公开 Linux TUN 继续关闭；前阶段完整密码授权闭环没有因本轮宿主未变而重复声称重新执行。macOS/iOS 与其余产品目标继续开发，代码未自动提交或推送。

本阶段保存文件的摘要见[证据索引](linux-desktop-system-services/evidence.json)。
