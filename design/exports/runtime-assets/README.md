# 应用使用的 Figma 原生资源

2026-10-20 重新通过 Figma MCP Bridge 从 RainLink 原生导出全部 44 个 SVG，当前资源直接使用本次导出；矢量路径未经重绘。品牌 PNG 重新导出后与原图逐像素及逐字节一致。源文件、节点 ID、目标路径及原始尺寸见 [manifest.json](manifest.json)。

- `app/assets/icons/`：36 个界面图标，包含最新左上角返回箭头。
- `app/assets/brand/mark.svg`：品牌标志。
- `app/assets/flags/`：7 个国家图标，保留多色填充；运行时国家未知时显示地球与「未获取」。

Flutter 通过 `RainlinkIcon` 使用原 SVG 路径，颜色跟随 `IconTheme` 和产品主题，保证按钮选中、禁用与深浅主题一致。Logo 仅按设计色值替换前景和背景，不改矢量形状。Windows 原生窗口控制图形继续使用原有窗口栏组件。

同一品牌节点另以 25.6 倍导出为 `brand-1024.png`（1024 × 1024）。`tools/generate_app_icons.py` 从该原始导出生成 Windows 的九种分辨率 ICO，以及 Android、iOS、macOS 和 Linux 的 28 个启动图标 PNG。Linux 的 512 像素图标嵌入 GTK runner，并作为桌面启动器资源打包；原生窗口使用 GTK 从同一资源缩放的 128 像素图标，避免超过常见 X11 属性请求上限，已核对实际窗口属性中的像素。iOS 按系统要求去除透明通道，补色仍为设计背景色；其余图标保留透明圆角。运行脚本的 `--check` 可验证全部生成结果。Pillow 版本锁定在 `tools/requirements-design.txt`。

字体按设计系统打包为本地资源，不依赖用户电脑是否安装字体：Inter 用于西文与数字，Noto Sans SC 用于中文回退，Roboto Mono 供等宽内容使用。Inter 与 Roboto Mono 下载自 Google Fonts 的 `ofl/inter`、`ofl/robotomono`；Noto Sans SC 使用本机已安装的同名字体文件。三者的 OFL 授权文本均随应用打包，下载自 Google Fonts 对应目录。

Noto Sans SC 的变量字体默认轴值为 `wght=100`，主题显式指定正文 400、标签 500、标题 600，避免中文回退到细体。字体家族、字号、行高与字重均集中在 `rainlink_theme.dart`。

`app/test/design_assets_test.dart` 逐个解码全部 SVG 并检查存在可见像素，另验证紧凑开关的 44 × 44 操作区域、键盘操作与禁用语义。
