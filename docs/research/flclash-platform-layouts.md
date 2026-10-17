# FlClash 跨平台布局与性能调研

调研日期：2026-10-16。

源码：[chen08209/FlClash](https://github.com/chen08209/FlClash)，`main` 分支检出的固定提交 `03f955382409a4a7ac1f3f92e46d9fcc6d39f106`（2026-10-14）。该提交的 `pubspec.yaml` 标记为 `0.9.0+2026101401`；这里研究的是源码快照，不据此判断各渠道的最新发布版本。

本次阅读源码与构建配置，并对照 RainLink 当前实现。未构建、运行或测量 FlClash 的内存、帧率、耗电和安装包大小；未修改 RainLink 产品代码。

## 结论

FlClash 使用一个 Flutter 工程和入口，共用业务状态与大部分页面，通过响应式布局适配桌面和手机。它将两个判断分开：

- **可用宽度决定界面布局**：移动、紧凑侧栏、宽侧栏。
- **操作系统决定原生能力**：窗口、托盘、快捷键、系统代理、Android 网络接管与核心通信。

RainLink 当前采用同一工程、业务共享、桌面与移动布局文件分开的方式。两者都合理，区别主要在布局切换规则；没有证据表明必须改成 FlClash 的目录或页面组织方式才能获得较好性能。

## 1. 布局如何选择

`ThemeManager` 使用 `LayoutBuilder` 取得可用尺寸并写入状态；`viewModeProvider` 根据宽度调用 `getViewMode()`。

| 窗口宽度（Flutter 逻辑像素） | 布局模式 | 导航形式 |
| --- | --- | --- |
| ≤ 600 | `mobile` | 底部导航，可选悬浮形式 |
| > 600 且 ≤ 840 | `laptop` | 侧栏，不允许展开文字标签 |
| > 840 | `desktop` | 侧栏，允许展开文字标签 |

因此，FlClash 的 Windows 窄窗口可以使用移动布局，Android 大屏也可以进入侧栏布局。界面变成移动布局时，Windows 的托盘和窗口等能力仍按 Windows 处理。

底部导航和侧栏由 `isMobileView` / `viewMode` 控制。导航项目也会按布局模式过滤，而不是所有入口在所有尺寸下同时展示。

证据：

- [尺寸采集：theme_manager.dart L60–70](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/manager/theme_manager.dart#L60-L70)
- [断点：constant.dart L133–134](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/common/constant.dart#L133-L134)
- [布局选择与侧栏展开条件：layout.dart L34–42](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/common/layout.dart#L34-L42)
- [底部导航：home.dart L70–151](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/pages/home.dart#L70-L151)
- [侧栏：app_manager.dart L230–285](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/manager/app_manager.dart#L230-L285)
- [导航过滤：navigation.dart L23–35](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/providers/state/navigation.dart#L23-L35)

## 2. 页面与业务怎么共用

单一 `main()` 完成初始化后，将同一个 Riverpod 容器传入 `Application`。导航项通过 builder 创建共用的 `DashboardView`、`ProxiesView`、`ProfilesView` 等页面；没有为桌面和 Android 各复制一套业务状态。

概览就是具体例子：同一个 `DashboardView` 先按平台筛选卡片，再按内容区宽度选择网格列数，卡片本身继续复用。概览网格有自己的 480 / 840 断点，与外层导航的 600 / 840 断点用途不同。

它也保留必要的平台交互差异。例如添加配置时，桌面二维码导入走桌面处理方法，手机则进入扫描页面。

证据：

- [入口与共享容器：main.dart L38–49](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/main.dart#L38-L49)
- [共用页面 builder：views/navigation.dart L16–38](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/views/navigation.dart#L16-L38)
- [卡片平台筛选：dashboard.dart L159–172](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/views/dashboard/dashboard.dart#L159-L172)
- [概览网格：dashboard.dart L195–221](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/views/dashboard/dashboard.dart#L195-L221)
- [概览网格断点：widget_metrics.dart L14–30](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/views/dashboard/widget_metrics.dart#L14-L30)
- [二维码导入的平台差异：add.dart L42–53](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/views/profiles/add.dart#L42-L53)

## 3. 没显示的页面如何减少开销

FlClash 没有在启动时展开所有页面的子树：主内容使用 `PageView.builder`，由框架按需调用页面 builder。跨多个标签切换时，还会重排临时索引，避免动画经过的中间页面被逐个构建和绘制。

但它也不是每次离开页面就销毁：`NavigationItem.keep` 默认是 `true`，`KeepScope` 使用 `AutomaticKeepAliveClientMixin` 保留页面状态；概览导航项显式设置了 `keep: false`。访问过并被保留的页面仍可能占用内存。

对于后台页面，它有两种明确控制：

1. `PageActivityScope` 标记当前页面，`TickerMode(enabled: isActive)` 暂停非当前页面由该模式管理的动画 ticker，并排除其焦点。
2. 连接列表、概览连接数、内存信息和 `TickBuilder` 等使用 `ActivePollingMixin`，只有应用处于前台且页面活跃时才继续轮询。停止时取消定时器，并用代次标记避免过期轮询继续排程；这不代表所有已发出的 I/O 都会被强制取消。

这些控制针对界面动画和界面数据更新，不能推导为切到后台就停止代理核心，也不能推导为所有隐藏页面都完全没有订阅或计算。

证据：

- [懒构建：home.dart L359–395](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/pages/home.dart#L359-L395)
- [跳过中间页面：home.dart L323–345](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/pages/home.dart#L323-L345)
- [缓存默认值：common.dart L19–28](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/models/common.dart#L19-L28)
- [缓存实现：keep_scope.dart](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/widgets/keep_scope.dart)
- [页面活动状态与动画暂停：home.dart L214–243](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/pages/home.dart#L214-L243)
- [轮询生命周期：active_polling.dart](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/widgets/active_polling.dart)

## 4. 原生服务如何隔离

`buildManagerStack(isDesktop: system.isDesktop)` 按操作系统只挂载对应管理器：

| 桌面 | Android |
| --- | --- |
| 窗口标题区域、窗口管理、托盘、快捷键、系统代理 | 网络接管管理、Android 生命周期、快捷设置磁贴 |

两端共用核心、连接变化、主题等管理层。

核心通信也有统一接口：`CoreController` 在 Android 选择 `CoreLib`，桌面选择 `CoreService`。桌面实现管理核心进程并使用 RPC，Windows 使用命名管道，其他桌面平台使用 Unix Socket；Android 则通过原生服务接入核心。

官方 README 的支持范围为 Android / Windows / macOS / Linux。本次不能将其 Android 实现视为已完成的 iOS 方案。

证据：

- [平台管理器选择：application.dart L25–55](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/application.dart#L25-L55)
- [系统判断来自 dart:io Platform：system.dart L32–40](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/common/system.dart#L32-L40)
- [核心实现选择：controller.dart L13–23](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/core/controller.dart#L13-L23)
- [桌面通信：service.dart L36–53](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/lib/core/service.dart#L36-L53)
- [支持平台：README.md L27–38](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/README.md#L27-L38)

## 5. 打包时另一平台的内容会怎样

这里需要分清三个层次：

| 内容 | 源码显示的处理方式 | 可以得出的结论 |
| --- | --- | --- |
| Dart 页面和布局 | 单一工程，按宽度选择布局；Release 使用 Flutter/Dart 编译优化 | 目标平台不可达代码可以被裁剪；依赖宽度且在目标平台仍能进入的布局，不应预期整套消失 |
| 图片、字体等资源 | 部分托盘图标通过 `platforms` 限定平台；其他目录共同声明 | 资源筛选需要显式配置，不能把代码裁剪等同于资源自动清理 |
| 原生核心和辅助程序 | 桌面构建 hook 读取目标 OS / CPU 架构，设置 Go 的 `GOOS` / `GOARCH`；Android 通过 Gradle 和 gomobile 构建 AAR | 各平台生成对应原生产物；Android ABI 的数量仍取决于构建参数，不是永远只有一个 ABI |

Flutter 官方文档明确说明：编译器会删除目标平台上不可达的代码，例如 Android Release 中 `Platform.isWindows` 分支里的 Windows 专用代码。这与“仅把两套布局放在不同文件夹”是不同机制。

FlClash 的布局按宽度切换，同一目标平台上移动/桌面布局都可能用到，因此不能宣称 Windows 包必然剔除全部移动布局。保留代码不代表相应组件已经挂载，也不代表它一直执行布局、绘制或轮询。

要确认某个产物实际保留了多少代码和资源，应查看目标平台 Release 的 `--analyze-size` 结果；要比较运行开销，则需要另做 profile 与内存测量。本次没有这两类实测。

证据：

- [平台资源声明：pubspec.yaml L96–109](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/pubspec.yaml#L96-L109)
- [桌面构建目标选择：core_builder.dart L96–126](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/plugins/setup/setup_hooks/lib/src/core_builder.dart#L96-L126)
- [Go 目标环境：go_builder.dart L76–80](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/plugins/setup/setup_hooks/lib/src/go_builder.dart#L76-L80)
- [Android ABI 选择：build.gradle.kts L42–48](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/android/core/build.gradle.kts#L42-L48)
- [Android gomobile 构建：build.gradle.kts L150–166](https://github.com/chen08209/FlClash/blob/03f955382409a4a7ac1f3f92e46d9fcc6d39f106/android/core/build.gradle.kts#L150-L166)
- [Flutter 官方：包体分析与平台代码裁剪](https://docs.flutter.dev/perf/app-size)

## 6. 对照 RainLink 与建议

| 维度 | FlClash | RainLink 当前实现 |
| --- | --- | --- |
| 布局选择 | 宽度决定移动 / laptop / desktop | `AppLayout.current` 按操作系统固定桌面 / 移动家族，各自内部适配尺寸 |
| 页面组织 | 共用页面较多，内部响应式排版 | 概览、设置、节点工具栏等已拆桌面 / 移动布局，共用卡片和状态 |
| 业务状态 | 同一 Riverpod 容器 | 同一数据库、Provider 与业务接口 |
| 平台核心 | 统一接口下选择桌面 / Android 核心实现 | `CoreGateway` 统一接口，桌面与移动分别注入；移动目前明确返回尚未接入 |
| 实时界面任务 | 部分页面已有活跃状态、轮询与动画控制 | 当前概览核心状态还是 `FutureProvider` 查询；接入持续流量和连接数据时需要设计生命周期 |

RainLink 本地依据：

- [布局选择](../../app/lib/design_system/layout/app_layout.dart)
- [外框选择](../../app/lib/app/navigation/rainlink_shell.dart)
- [业务与平台依赖注入](../../app/lib/app/dependencies.dart)
- [核心状态查询](../../app/lib/application/core/core_providers.dart)
- [现有布局说明](../UI_LAYOUTS.md)

建议保留 RainLink 已完成的独立布局结构，并优先借鉴以下机制：

1. 业务与基础组件继续共享；只有信息排布和交互确实不同的部分独立维护。
2. 接入真实流量曲线、连接列表、日志后，按页面是否可见以及应用前后台状态控制刷新；核心连接生命周期单独管理。
3. 页面缓存按需求开启，不为尚未访问的页面预先启动服务；需要保留状态的页面同时处理动画、订阅和定时器。
4. 原生适配和平台资源按构建目标选择，分别用 Release 包体分析与运行测量验证收益。

不建议仅为模仿 FlClash 将 RainLink 全部改成按宽度切换导航。RainLink 当前设计要求电脑保持桌面导航、手机保持移动导航，现有选择规则与这个要求一致。

FlClash 此快照在 CI 中使用 Flutter 3.47.6，RainLink 的 `.fvmrc` 为 3.27.4下一步干什么

应该平台资源声明和构建 hook 的新语法，应先验证 SDK 兼容性，再决定是否采用。
