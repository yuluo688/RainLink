# 桌面与移动端独立布局

同一 Flutter 工程、同一组路由和业务状态，两套布局文件。`AppLayout.current` 根据运行平台选择布局：Windows / macOS / Linux 使用桌面端，Android / iOS 使用移动端。窗口变窄或手机旋转时，只调整本端内部的排版，不切换到另一端的导航。

## 修改入口

以下路径相对于 `app/lib/`。

| 内容 | 桌面布局 | 移动布局 |
| --- | --- | --- |
| 导航与应用外框 | `app/navigation/desktop_shell.dart` | `app/navigation/mobile_shell.dart` |
| 页面标题、边距与操作区 | `design_system/layout/desktop_page_frame.dart` | `design_system/layout/mobile_page_frame.dart` |
| 概览卡片排版 | `features/overview/presentation/desktop_overview.dart` | `features/overview/presentation/mobile_overview.dart` |
| 节点搜索与工具栏 | `features/nodes/presentation/desktop_node_toolbar.dart` | `features/nodes/presentation/mobile_node_toolbar.dart` |
| 设置导航与内容排列 | `features/settings/presentation/desktop_settings.dart` | `features/settings/presentation/mobile_settings.dart` |
| 通用集合布局 | `design_system/layout/desktop_collection_layout.dart` | `design_system/layout/mobile_collection_layout.dart` |

桌面集合布局显示表头，移动集合布局使用卡片区域。节点、分组、规则、连接与日志共用这一入口，各自提供标题、操作和当前空状态；后续有真实列表数据时，可分别扩展两端的行与卡片。流量和代理链目前共用内容组件，页面外框分别由两端的 `PageFrame` 渲染。

## 共享的部分

- `*_page.dart` 保持路由入口，并持有两端共用的页面状态。例如节点搜索控制器、设置当前分类。
- `application/`、`domain/`、`data/` 和 `platform/` 继续负责业务、连接状态、持久化和平台能力。布局文件不创建另一套业务服务。
- 颜色、字体、Figma 图标、按钮、开关与卡片等基础组件共用。概览的状态订阅保留在 `widgets/overview_cards.dart`，设置面板与主题保存交互位于 `widgets/settings_panels.dart`。
- 现有 180 ms 页面过渡共用，侧栏和顶部固定。

## 新页面的组织方式

当两端需要不同的信息结构时，在同一功能的 `presentation/` 下增加 `desktop_*.dart` 和 `mobile_*.dart`，由 `*_page.dart` 使用 `AppLayout.current` 选择。布局中通过参数或现有 Provider 取得状态，交互调用同一个 Controller。

`LayoutBuilder` 继续用于本端内部的尺寸适配，例如桌面侧栏展开 / 收起和较大字体下的滚动。不要再使用屏幕宽度决定这是桌面端还是移动端。

## 验证

最初拆分布局时的 66 项 Flutter 测试及静态检查通过，覆盖五种目标平台的布局选择、窄桌面与宽移动屏幕、Android / iOS 旋转后的搜索保留，以及移动导航中的共享代理模式状态。2026-10-17 全量已扩展到 244 项，并加入移动标题区、iOS/Android 安全区一屏概览、320 宽大字和完整 IPv6 检查。原有字体放大、主题保存失败、快捷键和窗口按钮检查继续保留。

Windows Release 的运行核验见 [布局拆分验证](verification/platform-layouts.md)。移动标题区、首页一屏布局、完整 IPv6 和安全区续验见 [2026-10-17 移动布局](verification/mobile-layout-20261017.md)。Android / iOS 的上述结果属于组件测试，尚未在手机设备运行验证。
