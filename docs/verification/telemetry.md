# 连接与日志验收

日期：2026-10-16。覆盖 Windows 桌面，未据此宣称其他平台已接入。

## 实际行为

- 连接页读取 sing-box Clash API 实际快照；按稳定快照分页穿过私有 stdio，每帧最多 32 条，避免大型连接列表超过 128 KiB。显示真实目标、网络类型、可用进程、规则、出站与字节计数；不能识别的进程显示未知。
- 全分组关键词搜索、代理/直连筛选、暂停视图、关闭单条/确认关闭全部、CSV。关闭命令必须匹配活动会话，核心回读确认旧 ID 已消失；重连后的旧页面不能误关新会话。
- 核心 stdout/stderr 通过有界行读取器接入，采集 info / warning / error 等实际事件。日志先移除 ANSI、认证值、URL、令牌和 UUID，再进入内存与 IPC。超长原始行整行隐藏，不能靠截断泄露凭据片段。
- 核心缓存上限 2,000 条，独立宿主流标识和序号避免跨会话重复。Flutter 串行采集并提交 SQLite；重启后保留 7 天、最多 5,000 条，毫秒和同刻序号保持顺序。后台/页面暂停与采集状态分离；日志暂停只冻结视图。
- 清空前确认，先取核心清空游标再删除本地记录，避免轮询把已清空内容写回。取消导出不会产生成功提示；桌面原生保存对话框完成后实际写 CSV。导出使用当前筛选/暂停快照，CSV 会转义引号、公式前缀并包含 UTF-8 BOM。

## 验证证据

- `app/test/core_telemetry_test.dart`：7 项业务/边界测试，包括迁移、重启、毫秒顺序、容量/过期、采集和清空竞争、旧会话结果、关闭失败、CSV。
- `app/test/telemetry_ui_test.dart`：10 项组件测试，覆盖两尺寸、深浅主题和搜索/暂停/关闭/导出/确认清空。
- `native/host/internal/session/telemetry_test.go`：本地控制接口、分页、来源/认证信息脱敏、容量与真实核心 TCP 请求终止。
- 全量 Flutter 测试：155 通过；Go：41 个测试通过事件、5 个显式跳过（其中含父子测试记录），无失败；`go vet` 与 Flutter analyze 通过。原始结果在本机 `build/telemetry-*-test.jsonl`。
- `app/integration_test/windows_telemetry_test.dart`：Windows 实际 Flutter → Host → sing-box → 本机 HTTP 长连接，经页面按钮关闭真实请求，并通过原生另存为写出 CSV、重新读取校验。14 条核心事件进入数据库。详情见 [运行证据](telemetry/windows-evidence.json)、[连接](telemetry/connections-real.png)、[日志](telemetry/logs-real.png)。它证明本机链路，不代表第三方机场线路稳定。
- `app/integration_test/telemetry_visual_test.dart`：Windows 渲染器生成 8 张明确标为 fixture 的截图，尺寸 960×640 / 1440×900、深色/浅色；数据仅用于视觉测试。
- HY2 本地协议用例取消无关公网诊断，QUIC 单独采用有界 5 秒握手期限，载荷和错误认证断言保持不变。针对原 1.5 秒期限的偶发超时，连续三轮通过；不据此宣称真实机场无间歇故障。

## Figma 核对

本次直接读取当前 Figma `2:18738`（连接）和 `2:19439`（日志）。沿用左导航、标题、三指标卡、筛选工具栏、圆角表格与状态色；960×640 使用紧凑导航及分行工具栏，列表在卡内滚动。日志行避免使用输入组件的额外高度；宽桌面搜索框限制为 360 px。

连接、日志、搜索、关闭、下载五个 SVG 已从当前 Figma 重新导出，与运行资产逐字节相同，见 [哈希记录](telemetry/icon-verification.json)。未用 Material 图标替代。完整产品其余页面与移动端仍待继续实现/逐页验收。
