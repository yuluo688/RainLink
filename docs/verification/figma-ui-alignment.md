# Figma 视觉与资源校准

日期：2026-10-16。源文件：[RainLink](https://www.figma.com/design/d2zbhuqMRbUMRLs6wIssFJ/RainLink)，设计系统母版通过 Figma MCP Bridge 实时读取并导出，节点 ID 与路径记录在 [资源清单](../../design/exports/runtime-assets/manifest.json)。

## 实现

| 项目 | 调整 |
| --- | --- |
| 界面图标 | 36 个 Figma 原生 SVG，通过统一 `RainlinkIcon` 接入导航、概览、节点、设置、返回与空状态；颜色跟随选中、禁用和主题 |
| 品牌与国家 | 使用原生品牌 SVG、7 个国家 SVG；没有真实国家结果时保持地球与「未获取」 |
| 系统应用图标 | Figma 品牌节点原生导出 1024 PNG，生成九种分辨率 Windows ICO，以及 Android / iOS / macOS 的 27 个 PNG；生成器与依赖版本已保存 |
| 字体 | 本地打包 Inter、Noto Sans SC、Roboto Mono 和 OFL；中文变量字体显式指定 400 / 500 / 600，修复默认 100 字重造成的发虚 |
| 导航与控件 | 完整侧栏 40 高、18 图标、13 标签；紧凑侧栏 44 高。开关视觉 36 × 22、滑块 16、操作区 44 × 44。模式选择采用圆角矩形分段按钮 |
| 节点与分组 | 节点增加与稿子一致的搜索 / 分组 / 代理链 / 测速工具栏，表头缩减留白并按列比例对齐；分组空状态去掉稿子中没有的表头 |
| 设置与返回 | 设置分类栏使用有边框的圆角表层与选中背景；代理链改为标题左侧返回箭头 |

## 验证

- Dart 格式与 Flutter 静态检查通过。
- 本轮完整 55 项 Flutter 测试通过；最终字体与选中背景调整后，相关 23 项布局、导航、搜索、主题、SVG 绘制和开关语义测试再次通过。
- 44 个 SVG 逐个解码并验证可见像素；开关覆盖边缘点击、键盘操作与不可用状态。
- 图标生成器 `--check` 验证全部 27 个 PNG 和九种分辨率 ICO。
- Windows x64 Release 重新构建并实际启动，提取可执行文件应用图标确认已替换为 RainLink 标志。打包资源与源文件的哈希核对结果见 [构建记录](figma-ui-build.json)。
- 125% 缩放下，默认窗口物理尺寸 1200 × 800，Flutter 客户区 947.2 × 632.8；较宽窗口物理尺寸 1625 × 900，客户区 1287.2 × 712.8。深浅主题均实际核对，概览内容完整。

检查后恢复原来的「跟随系统」偏好，当前呈现深色主题，保持居中的默认紧凑窗口与概览。

## 实际运行画面

- [紧凑概览 · 深色](windows-figma-icons-compact-dark.png) / [浅色](windows-figma-icons-compact-light.png)
- [较宽概览 · 深色](windows-figma-icons-wide-dark.png) / [浅色](windows-figma-icons-wide-light.png)
- [节点与搜索](windows-figma-icons-nodes-dark.png)
- [设置分类](windows-figma-icons-settings-dark.png)
- [代理链返回箭头](windows-figma-icons-chain-dark.png)

截图来自运行中的 Windows Release。节点导入、网络核心、系统代理、TUN 和遥测仍待实现，保持未连接及空状态；未使用设计稿示例 IP、国家、节点或流量充当运行数据。其他平台图标资源已生成，未进行对应原生构建或设备验证。
