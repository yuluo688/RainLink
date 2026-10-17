# 独立布局验证 · 2026-10-16

布局入口改为按平台选择。桌面与移动端分别维护导航外框、页面外框、概览、节点工具栏、设置排版及集合模板，继续使用同一个路由和业务状态。目录和修改方法见 [两端布局说明](../UI_LAYOUTS.md)。

## 自动检查

- Dart 格式检查通过，75 个文件无格式变更。
- Flutter 静态分析通过，无诊断。
- 全部 66 项测试通过，包括原有业务与 UI 检查及新增的 8 项平台布局检查。
- 三种桌面平台在 640 × 640 组件视口下保留侧栏和桌面状态栏；Android / iOS 在 1024 × 768 视口下保留底部导航，节点页隐藏桌面表头。
- Android / iOS 从 393 × 852 旋转到 852 × 393 后，节点搜索控制器与查询内容保留，未出现布局异常。
- 移动端代理模式在页面往返后保留，使用同一组 Provider。

移动端结果来自 Flutter 组件测试中的目标平台模拟，尚未在 Android / iOS 真机验证。

## Windows 实际运行

Windows x64 Release 构建并启动成功。默认窗口为 960 × 640 逻辑像素，在 125% 缩放下测得客户区为 947.2 × 632.8。实际点击并核对概览、节点与设置，保持紧凑侧栏、一屏概览、现有中文字体和 Figma 图标；核验后返回概览，保留原主题偏好。

- [概览](windows-independent-desktop-overview.png)
- [节点与桌面表头](windows-independent-desktop-nodes.png)
- [设置](windows-independent-desktop-settings.png)
- [构建与校验记录](platform-layouts-build.json)
