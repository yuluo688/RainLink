# 桌面窗口栏 · 2026-10-15

顶部窗口控件已直接落地到 Flutter。Windows / Linux 使用隐藏系统标题栏，与现有状态栏共用 56 px 高度；macOS 保留原生窗口栏。没有增加第二排应用标题。左侧品牌与右侧连接状态对齐。

最小化、最大化／还原、关闭使用 40 × 32 px 控件、8 px 圆角和细线图标，提供中文工具提示、键盘焦点边框与悬停状态。关闭按钮悬停时显示淡红表层和红色图标。控件颜色随应用主题改变，原生最大化事件同步更新“还原窗口”。标题区与品牌区支持拖动、双击，Windows 标题区提供右键系统菜单。

本轮验证环境为 Windows x64、125% 显示缩放、Flutter 3.27.4 / Dart 3.6.2。Windows Release 已构建并在真实窗口中检查；移动端通过组件测试确认不创建桌面控件。macOS / Linux 尚未实机验证。

| 检查 | 结果 |
| --- | --- |
| Dart 格式与 Flutter 静态分析 | 通过 |
| Flutter 单元与组件测试 | 42 项通过，其中 7 项覆盖窗口控件与平台边界 |
| 实际点击最小化 | 原生 `IsIconic` 为 true；还原后恢复原窗口 |
| 实际点击最大化／还原 | 原生 `IsZoomed` 依次为 true / false |
| 标题空白双击 | 原生最大化与还原正常；测试位置在顶栏顶部空白处 |
| 标题及品牌拖动 | 窗口位置 (60,30) → (70,40) → (60,30)，尺寸保持不变 |
| Windows 标题右键 | 系统窗口菜单实际显示，还原、移动、大小、最小化、最大化、关闭入口可见 |
| 原生边缘缩放 | 右侧原生边框拖动后物理宽度从 1800 px 变为 1725 px，高度保持 960 px |
| 深浅主题 | 从设置切换并检查实际控件，验证后恢复原浅色偏好 |
| 较小窗口 | 960 × 640 逻辑外框尺寸下窗口按钮完整显示 |
| 实际点击关闭 | Release 进程退出；随后重新启动 |

截图来自实际运行的 Release，没有用设计示例替代运行界面：

- [深浅主题顶栏](windows-custom-chrome-preview.png)
- [浅色概览](windows-custom-chrome-light.png)
- [深色概览](windows-custom-chrome-dark.png)
- [关闭悬停](windows-custom-chrome-close-hover.png)
- [深色关闭悬停](windows-custom-chrome-dark-close-hover.png)
- [最大化](windows-custom-chrome-maximized.png)
- [较小窗口](windows-custom-chrome-compact.png)
- [系统窗口菜单](windows-custom-chrome-system-menu.png)
- [边缘缩放](windows-custom-chrome-edge-resize.png)

最新 Release 的 SHA-256 与宿主一致性记录在 [构建记录](window-chrome-build.json)。

实现复用现有 `window_manager`，没有增加依赖或修改生成的平台注册文件。窗口平台调用与界面组件分开；命令失败记录异常并提示，监听器销毁时解除，晚到的初始化结果不会更新已销毁的控件。拖动和系统菜单由原生交互循环结束或 Escape 取消，避免把用户操作时间误判成超时。
