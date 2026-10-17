# Figma 图标实时复核

2026-10-17：通过当前连接的 RainLink Figma 文件重新导出，未修改设计稿或应用资产。此项检查与同期 Linux 网络测试分别记录。

| 范围 | 结果 |
| --- | --- |
| 界面图标、品牌 SVG、七种国家标识 | 44 / 44 与应用文件逐字节 SHA-256 一致 |
| 品牌 1024 PNG | 当前 Figma 原生导出与既有生成源的尺寸及完整 RGBA 像素字节一致 |
| iOS / macOS / Android 原生 PNG | 27 个由既有生成器重新计算核验通过 |
| Windows ICO | 9 种分辨率核验通过 |

资源节点、当前原生导出路径和双方摘要见 [icons.json](runtime-audit-20261017/icons.json)；生成器回执见 [native-icons-check.log](runtime-audit-20261017/native-icons-check.log)。Figma 文件为 [RainLink](https://www.figma.com/design/d2zbhuqMRbUMRLs6wIssFJ/RainLink)，Bridge 文件标识为 `unsaved-mva99nf3-128z4u3c`，当前三个页签为桌面端、移动端、设计系统/组件/流程。

原生检查使用捆绑 Python/Pillow 运行 `tools/generate_app_icons.py --check`。应用图标没有重新生成或替换。这里证明资源与当前设计稿一致，未重新运行 Flutter 页面截图、各平台安装包构建或完整页面/弹窗布局检查；这些仍属于后续验收范围。
