# 概览近期连接与紧凑布局续验

日期：2026-10-20。基于 `0f80987cac940518e77f23816c5490223debff76` 和当前未提交修改；完整五平台目标仍在进行。

## 行为与布局

桌面概览补上 Figma 底部的「最近连接」与「查看全部」。摘要显示核心实际观测到的目标地址、代理/直连和请求开始时间，点击进入现有连接列表，可以继续筛选或关闭请求。没有把整体出口探测延迟当成单个请求的延迟。

当前只保留当前控制器最近观测的一条请求，不写入数据库；进入概览或连接页时采样，离开这两页后停止新采样。切到后台暂停，恢复前台继续；断开或切换会话清空摘要，迟到响应不能覆盖新会话。空列表、读取失败和暂停状态有各自显示。关闭请求后可以继续显示本次会话的最近观测，不将它标为仍然活跃。

概览与连接页复用原控制器和宿主通道。默认 960×640 下保持一屏；连接卡根据字号计算高度，紧凑布局的次级选择按钮为 32 像素，节点健康行使用 24 像素。全量回归曾发现新增底部行挤掉第二个节点状态，现已调整连接卡、趋势图与健康卡间距，保留两行健康信息。移动端继续使用独立布局，没有增加首页信息行。

## 验证

- Dart 格式和 Flutter 静态分析通过，完整 Flutter 单元/组件回归 **468 项通过**。包含小窗口的有数据/空状态、健康区、稍大字号、自然滚动、摘要跳转、后台暂停和离页释放。
- Windows 与 Linux 的真实核心集成各一项通过。界面从概览连接本地 HTTP 测试节点，经真正 sing-box 取得完整 HTTP 200 响应；另保持一条请求供核心观测，概览显示真实目标，跳转后从连接页关闭它，断开后摘要清空。
- 两套桌面原生渲染器各通过三个布局场景，各生成 **54 张**截图：八个桌面主页面的两种尺寸及深浅主题共 32 张，五个移动主页面的两种尺寸及深浅主题共 20 张，移动大字号/IPv6 两张。合计 **108 张**；这些移动尺寸截图不代表 Android/iOS 设备验收。
- 当前 Figma 已读取概览节点 `2:17066`，底部记录节点为 `I31:181510;77:121741`。全部 44 个 SVG 继续与当前原生导出逐字节一致；品牌图生成检查通过 28 个 PNG 和九尺寸 ICO。
- 729 项当前产品源码输入与 Linux QA 副本匹配，没有缺失或摘要差异。原始日志、截图清单、源码及二进制摘要见[证据索引](overview-recent-connections/evidence.json)。

真实请求测试使用内存数据库与只允许 loopback 目标的本地代理，没有切换系统代理或 TUN。Windows 核心为 `1.12.25-rainlink.1`，Linux 为 `1.12.25-rainlink.2`；Linux 环境沿用前轮 Debian 13、普通 UID 1000、Xvfb/Openbox 和独立 D-Bus/Secret Service，GUI 网络只有 loopback。此处真实请求集成使用 Debug runner。

## 当前预览

普通 Linux 用户完整执行 `bash tools/dev.sh package`，重新生成 **0.1.0+4** 的 `build/RainLink-linux-x64-preview.tar.xz`，32,202,636 字节：

```text
395f7875c5a612d5969c1adfef89093f6d6074860f2a737402ccbcdc0f917a03
```

归档中的 77 个条目（76 个载荷文件和一份清单）经过摘要与执行权限检查，包含新界面的 AOT、宿主、锁定核心、KDE 辅助程序、Figma 资源及许可。Release 另在新目录解压，以独立空数据目录启动，确认默认 960×640 概览与底部摘要入口，再通过右上角关闭并确认宿主和核心退出。该 Release 启动检查不替代前轮的 GNOME 接管及连接中关闭恢复验收。

Release 退出码为 0，但日志仍记录 `atk_socket_embed`、`FlutterEngineRemoveView`、`g_object_weak_unref` 和失效 `FlBinaryMessenger` 的原生诊断；原文保存在[退出诊断日志](overview-recent-connections/linux-release-diagnostics.log)。本轮未定位这些 GTK/Flutter 诊断的原因，正常退出和无残留不能证明所有关闭警告已经解决。

- [Windows 真实请求](overview-recent-connections/windows-overview-960-real.png)
- [Linux 真实请求](overview-recent-connections/linux-overview-960-real.png)
- [Linux 最终 Release 窗口](overview-recent-connections/linux-release-960.png)
- [Figma / 当前桌面布局对照](overview-recent-connections/figma-desktop-comparison.png)，运行图中的数据为 fixture。
- [完整布局截图清单](overview-recent-connections/layout-captures.json)

前轮[Linux 桌面预览](linux-desktop-preview.md)及其源码/归档摘要保持原样。当前没有重新生成 Windows Release，也没有提交或推送本轮修改。

## 继续范围

UI 结构和图标继续对齐设计稿，数据按实际来源显示。网络质量仍为真实请求耗时，没有设计样例中的综合评分；趋势图底部仍显示核心状态。完整弹窗流程和真实移动设备仍需继续核对。

公开 Linux `capabilities.tun` 继续为 false。活动桌面认证与 GUI 安装闭环、普通 broker 在写入期间的端到端取消、完整 GNOME/Plasma/Wayland、发行版兼容与正式分发、macOS 宿主、iOS 网络扩展和 Android 真机验收仍按[实现清单](../IMPLEMENTATION_STATUS.md)推进。
