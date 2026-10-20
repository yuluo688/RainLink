# Linux 桌面预览、真实连接与 Figma 核对

日期：2026-10-20。基于 `0f80987cac940518e77f23816c5490223debff76` 及本轮未提交修改；产物为本地开发预览，尚未发布。

## 结果

`bash tools/dev.sh package` 已在普通 Linux 用户下完整执行，生成 **0.1.0+4** 的 `build/RainLink-linux-x64-preview.tar.xz`，32,201,584 字节，SHA-256：

```text
0adfc45d544a1b16272c83765b318f23e290004840bde1306016820bfd2b8cb8
```

包内包含 Flutter Release/AOT、Go 宿主、固定核心、Qt6/KConfig6 辅助程序、桌面启动器、图标、字体、许可和核心对应源码。77 个归档条目、55 项应用资源通过校验；归档逐文件摘要与执行权限已验证，不含用户数据库。解压至不同目录后直接运行 `RainLink/rainlink` 已通过。

实际解压后的 Release 通过界面添加带认证的 HTTP 测试节点，重开后保留节点和选择；连接实际 sing-box 后，通过本地测试代理取得 HTTP 200 及独立响应回执。开启 GNOME 系统代理后回读为 `manual`，再点击窗口右上角关闭，程序退出码为 0，dconf 配置与接管前逐字节一致，无残留宿主、核心或监听端口。见[连接回执](linux-desktop-preview/release-connection-evidence.json)与[关闭恢复](linux-desktop-preview/release-close-evidence.json)。

## 环境与边界

环境为 Debian 13 用户空间、WSL Linux 内核、普通 UID 1000、Xvfb/Openbox、独立 D-Bus 与 Secret Service；图形运行置于只有 loopback 的私有网络命名空间。GNOME 配置后端真实运行，但这不代表完整 GNOME Shell、Plasma、Wayland 或物理设备验收。未访问真实订阅、用户数据库或用户密钥环，未改变宿主桌面代理。

Flutter 3.27.4 / Dart 3.6.2、Go 1.25.5、GTK 3.24.49、Qt 6.8.2、KConfig 6.13.0、glibc 2.41。此预览仅在该环境验收，其他发行版的运行库兼容性仍待验证。核心在 Linux 原生重建后与锁定摘要 `640e5293d90b94c71318031284e65cf8121d99ee9c06482f021ed77c9f3fa96d` 一致。

首次准备环境时遇到磁盘空间、软件源签名生效时间、终端作业暂停和跨系统 SDK 缓存文件大小写问题，修正隔离环境后重新执行。SQLite 官方 URL 在当前网络重置或停滞，使用既有 Windows 官方 URL 下载缓存，核对 SHA-256 后复用；未关闭 TLS 或摘要校验。完整原始日志保留在 `build/qa/linux-gui/`，SDK、Go 与 SQLite 输入来源记录随本报告保存。

运行日志保留了 GTK `atk_socket_embed` 诊断；本轮未验收辅助功能。

## 修复与检查

- 修复从只读 Go 模块缓存复制目录后，普通用户无法加入本地扩展或重试构建的问题；上游缓存保持只读，新增两项回归。
- KDE 辅助程序使用 Ninja，与 Flutter 构建依赖一致，独立子目录兼容既有 Makefile 缓存。
- SQLite 源码固定 SHA-256，并设置下载超时；中途配置失败后重试，不再回退安装到 `/usr/local`。
- Linux 原生窗口嵌入 Figma 同源品牌图。512 像素直接注册曾导致 X11 无图标，现使用 GTK 缩放的 128 像素窗口图标；实际 `_NET_WM_ICON` 像素与同源缩放结果一致，启动器继续使用 512 像素。
- Linux 打包回归 8 项、Windows 打包回归 5 项、只读源码回归 2 项通过；Linux 执行权限与符号链接检查无跳过。
- Flutter 静态分析无问题，修改的集成测试格式检查、3 项 SVG/开关测试、1 项真实 SQLite/宿主冒烟测试通过。并非重新执行全量 460 项测试。
- Linux 渲染器执行 3 项布局测试、1 项权限服务视觉测试，通过 38 张布局截图与 40 张状态截图。移动尺寸截图验证共享界面布局，不代表 Android/iOS 设备运行。权限服务截图使用 fixture，不代表实际图形授权成功。

## 界面核对

通过当前 Figma Bridge 重新读取 8 个桌面主页面，原生导出全部 44 个 SVG，与本轮资源逐字节一致；品牌 1024 PNG 与仓库原图逐像素及逐字节一致。28 个原生 PNG 和 9 尺寸 ICO 经生成器核对。SVG 增加 LF 属性，避免 Windows 检出时改变原始导出字节。

实际窗口默认 **960×640**，8 个主页面完成原生渲染；最大化、还原、最小化和关闭均通过，最终窗口无额外系统标题栏。概览在普通字号下一屏展示，保持 Figma 的连接卡、代理控制、独立出口、统计、趋势和节点健康层级。宽屏和紧凑样例、浅色、移动尺寸与大字号均完成 Linux 渲染检查。

这是结构、资源与交互核对，不能称为所有画面逐像素相同。实际版本、连接状态、未知出口、网络错误和探测结果随真实数据变化；网络质量显示请求延迟，未使用设计样例中的综合评分，趋势底部仍采用当前核心状态。更完整的近期连接摘要、全页面弹窗和真实移动设备仍需继续核验。

- [实际概览 960](linux-desktop-preview/release-overview-960.png)
- [实际系统代理连接中](linux-desktop-preview/release-system-proxy-active.png)
- [实际添加弹窗](linux-desktop-preview/release-add-node-dialog.png)
- [Figma / Linux 渲染器对照，数据为 fixture](linux-desktop-preview/figma-linux-comparison.png)
- [权限服务显示，数据为 fixture](linux-desktop-preview/service-current-960-dark-fixture.png)
- [验收摘要与证据摘要](linux-desktop-preview/evidence.json)

## 后续

公开 Linux `capabilities.tun` 继续为 `false`。活动桌面认证弹窗、GUI 服务安装闭环、普通 broker 写入期间取消、正式系统安装包/卸载与在线更新、真实 GNOME/Plasma/Wayland、KDE5、切网/休眠/注销仍未完成。macOS 宿主、iOS 网络扩展和 Android 真机验收继续按[完整实现清单](../IMPLEMENTATION_STATUS.md)推进。
