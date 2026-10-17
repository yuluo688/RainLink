# 分流规则验收

2026-10-16，Windows，sing-box 1.12.25-rainlink.1。

已替换占位页：完整域名、域名后缀、IPv4/IPv6 CIDR、兜底；添加/编辑弹窗，筛选，启停，上下移动，确认删除。唯一兜底固定最后，目标为当前所选节点、单个节点、分组、直连或拦截。代理链目标由后续代理链模块补齐。

规则以带修订号的单条 JSON 原子保存于已有 SQLite preferences；无数据库版本变更。缺省规则保留局域网、回环和链路本地地址直连。保存前 Host 使用受控编译器及 bundled core check 校验，保存事务再次确认修订和引用；失败不替换原数据。数据损坏明确报错，不能悄悄重置规则。

连接时同一事务冻结全部规则与所引分组的记忆节点；空组或删除引用报错，已删除的记忆节点回退首个节点。默认代理、每个规则出站的认证/传输/证书选项和 Hysteria2 上游策略均独立编译。Host 回传实际规则修订与节点绑定，Flutter 核对。连接中改选或修改规则提示重连后应用，不热替换现有会话。

验证：

- Flutter 静态分析无问题，全量 170 项测试通过。新增 10 项业务回归及 5 项组件测试，包括持久化、并发修订、删除竞态、CIDR、失效引用、取消期间迟到解析、UTF-8 帧上限、交互及大字/键盘边界。
- Go vet 通过；全量真实核心测试 44 个通过事件、5 个显式 skip 事件。新增真实请求验证完整域名优先于后缀、分组独立出站、局域网直连、拦截、兜底、global/direct 覆盖、失败校验保留会话及冻结目标。
- Windows 集成通过真实 UI 添加 CIDR 并选分组，实际请求经组内记忆节点；切换全局走默认节点、直连走本地源站。连接中编辑规则仍走旧分组，重连后采用新直连规则。临时数据库、本机代理 fixture、不修改系统代理；这不代表远程机场验证。
- Windows 原生 Flutter 渲染 1440×900、960×640 与 393×852 两主题，列表/弹窗共 12 张 fixture 截图。移动截图验证独立布局，移动网络接管尚未实现。
- 连接和日志的 Windows 原生回归也通过：真实请求关闭、核心日志入库、原生保存对话框及 CSV 文件。测试节点先经节点仓库保存，再按生产连接校验解析。
- 刚从当前 Figma 导出的 rules、plus、more、close 四个 SVG 与运行资产逐字节相同。布局按紧凑桌面适配；排序/停用/删除收在操作菜单，兜底只显示编辑。

证据：`routing/windows-evidence.json`、`routing/rules-real.png`、`routing/icon-verification.json`、`routing/*-fixture.png`、`routing/figma-rules.png`。原始结果：`build/routing-flutter-test.jsonl`、`build/routing-go-test.jsonl`、`build/routing-windows-integration.log`、`build/routing-visual-integration.log`。

边界：最多 256 条规则、32 个独立引用；完整 IPC UTF-8 帧仍须小于 128 KiB，超限在发送前拒绝。域名填写 ASCII/Punycode；不支持通配符和任意脚本。保存校验用占位出站验证规则语义，实际节点参数和凭据于连接前完整检查。尚无规则导入、规则集下载或远程热更新；这些不在当前设计的最小流程内。

另用用户原有授权的两条 Hysteria2（IP 字面及域名各一条）重新验证：两条均取得真实 HTTPS 响应、出口观测和字节计数，测试监听均已关闭。节点凭据、证书摘要和端口跳跃保持；用户数据库内容/偏好及系统代理保持。某条线路的独立请求观察到不同国家出口，因此继续以每次真实出口查询为准，不用节点名称推断。该轮成功不能排除此前观察到的间歇超时。脱敏结果：`routing/hysteria2-remote.json`。

Release 已重新构建，核对 Flutter Release engine 与核心哈希，预览包为 `build/RainLink-windows-x64-routing-preview.zip`；校验见 `routing-build.json`。本次还统一了弹窗的 12 px 圆角、边框及中性表面，取消 Material 默认染色，并用 Figma 下拉箭头与正文样式显示规则选项。
