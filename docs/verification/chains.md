# 可视化代理链验收

2026-10-16，Windows，sing-box 1.12.25-rainlink.1。

节点工具栏的「代理链」入口已替换占位页。支持 2–5 跳、搜索节点、更换、上移/下移、移除、测试和取消、保存并选中；名称栏右侧菜单提供新建、打开已保存链和确认删除。链名 1–64 个字符，最多保存 32 条，同一节点不能重复。HTTP 上游无法转发后续 Hysteria2 所需 UDP 时明确拒绝。更改节点或顺序后历史测试失效，改链名不让相同路径的测试失效。

保存只更新选择，连接和代理模式仍在概览。代理链与单节点选择互斥，选分组恢复其记忆节点并取消链选择；不改变组内记忆。连接中修改链或选择不会替换活动路径，断开重连后应用。规则出站也支持代理链。

链以节点 ID 列表、名称、修订及脱敏测试结果保存到 SQLite preferences 的 `routing.chains`，仍为 schema 4；不复制服务器或认证。保存前经实际核心 check 校验，事务内重新核对链和节点修订；失败保留原链。失效节点引用保留供修复，连接前报错，不静默换点。连接事务冻结主链和规则引用链的所有节点，Host 回传目标类型/修订与逐跳绑定，Flutter 核对后才提交已连接。

前一跳通过 detour 串入下一跳，仅入口可使用物理网卡和独立上游 DNS。协议认证、证书及传输设置沿用已有编译器。测试使用 `serve-test` 私有进程及临时运行目录，禁止系统接管；正常 Host 不接受测试命令。逐前缀用实际核心访问固定 HTTPS 204 站点，每段最多 8 秒。失败说明到哪一跳的路径未通过，不能凭此认定某个服务器故障；耗时为整个前缀往返，不是节点间独立 Ping。

验证结果：

- Flutter 静态检查通过，全量 183 项通过；新增 10 项代理链业务回归及 3 项 UI 测试，覆盖保存、凭据边界、并发修订、节点失效、规则绑定、选择互斥、测试响应完整性、取消、搜索/排序/菜单、失败保留及移动端 1.3 倍字号。
- Go vet 通过；全量 48 项通过、5 项明确跳过、无失败。真实核心验证双 HTTP 代理顺序及逆序、规则链出站、错误认证的失败前缀、请求中取消并释放源站连接、测试不替换已有会话且不启用系统代理。
- Windows 原生集成通过 UI 添加并保存两跳，再从概览连接；实际本地请求按 A → B → 源站，修改后保持旧路径，重连变为 B → A → 源站。隔离 Host 取消不影响活动会话。测试使用临时数据库、本机 CONNECT 代理，不修改用户数据或系统代理。
- 1440×900 / 960×640 / 393×852，两主题，编辑器和节点选择弹窗共 12 张 Flutter 原生截图。960×640 的两跳与操作区一屏可见；移动单列及 44 px 按钮，长内容自然滚动。链管理收进名称栏；节点名称清理地区标注，避免 Windows 将旗帜显示为小号字母。
- 从当前 Figma 导出的 11 个本模块 SVG 与运行资产逐字节比较，见 `chains/icon-verification.json`。设计原图为 `chains/figma-desktop.png` 和 `chains/figma-mobile.png`。

证据：`chains/windows-evidence.json`、`chains/overview-real.png`、`chains/*-fixture.png`、`build/chains-flutter-test.jsonl`、`build/chains-go-test.jsonl`、`build/chains-windows-integration.log`、`build/chains-visual-integration.log`。fixture 截图中的节点、12/24 ms 和既有出口样例为排版数据。

Release 构建成功，Flutter Release engine 哈希匹配。独立预览包为 `build/RainLink-windows-x64-chains-preview.zip`，41,298,606 字节，SHA-256 `9bc7c8ddaffe99d96122b1e7c9e58b144b79eb27e5c3cdf934111fdd98fb2923`；Host/Core 哈希见 `chains-build.json`。已启动该 Release，以实际用户库核对默认紧凑窗口：概览完整一屏显示，代理链编辑器入口正常，未保存测试链或启用系统代理。截图为 `chains/release-overview.png`、`chains/release-chain.png`。

边界：本次转发验收是本机 HTTP 双跳，不能据此声称所有远程服务商、多协议及 UDP 组合都已实测。本地库未保存此前授权的 HTTP 节点对，未执行公网双跳测试，见 `chains/remote-http-chain.json`。移动编排 UI 已提供，移动网络服务、安全存储、macOS/Linux Host 和 TUN 仍以实现清单为准。
