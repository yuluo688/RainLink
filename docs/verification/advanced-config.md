# 高级配置续验 · 2026-10-17

入口为「设置 → 核心引擎 → 高级配置」，桌面保留六分类，移动端进入局部详情，左上角返回核心页。YAML / JSON 可转换，提供校验、确认应用，以及「⋯」内的恢复上一版、清除覆盖和导出。默认 `{}` 沿用界面设置，不默认新增 DNS 或分流策略。

## 字段与合并

采用受控 sing-box 片段，不接受任意完整核心配置。节点、认证、入站、端口、控制 API、TUN 与权限流程由 RainLink 管理。未知字段明确拒绝，不静默忽略。最多 16 KiB、12 层、2,048 个展开值；拒绝重复键、循环/重复 YAML 引用。错误只包含安全中文说明，不引用粘贴内容或原始核心输出。

| 片段 | 支持字段 |
| --- | --- |
| log | level（debug/info/warn/error）、timestamp |
| dns | servers、final、strategy、disable_cache、disable_expire、independent_cache、cache_capacity、rules |
| DNS server | type（local/udp/tcp/tls/https）、tag、server、server_port、HTTPS path、tls.enabled、tls.server_name |
| DNS rule | domain/domain_suffix/domain_keyword 列表；server 或 action: reject |
| route.rules | 域名匹配、ip_cidr、ip_is_private: true、port、network 列表；outbound: proxy/direct 或 action: reject |

最多 8 个 DNS 服务器、各 64 条 DNS/分流规则、每条同类条件 64 项，缓存容量 0–65,536。TLS 必须启用证书校验，不接受认证、查询参数、detour、文件路径或额外监听。省略 DNS tag 时为 server-1、server-2；内部增加独立前缀，不能覆盖上游 DNS。system 表示系统 DNS，default 表示网络页的 DNS；添加服务器后默认使用第一个，或由 final 指定。域名服务器使用网络页的引导 DNS。

顺序为界面生成配置 → 高级片段 → TUN 保护 → 实际 sing-box check。TUN DNS 接管优先；概览直连/全局模式先于高级分流，高级分流先于规则页。原规则的节点/分组/代理链快照和 detour 保留，新增远程 DNS 在 TUN 下绑定物理上游接口。网络页提示高级覆盖及基础 DNS 编辑/测试范围；核心页显示覆盖后的日志级别，避免表单与片段互相覆盖。

```yaml
log:
  level: info
dns:
  servers:
    - tag: secure
      type: https
      server: dns.alidns.com
  final: secure
  independent_cache: true
route:
  rules:
    - domain_suffix: [example.com]
      outbound: direct
```

## 应用与恢复

校验使用独立诊断宿主，不读取节点凭据，不改变活动会话或系统网络。校验时仍可输入；改动会取消旧校验，迟到回执不生效，离开时回收校验宿主。编辑或基础网络设置变化使校验失效，必须重新校验后才能应用。

应用前确认：未连接时只保存，下次连接使用；已连接时保留实际活动目标、规则、模式与接管选项重连，不采用节点页尚未应用的新选择。重连失败尝试恢复原连接，不提交新设置；存储失败也恢复应用前的连接。连接变化/取消使旧确认失效，不能在用户断开后擅自重连。

当前片段与上一版在同一个 SQLite 事务写入，复用 preferences，无 schema 变化。恢复先载入草稿，校验和确认后才应用；恢复后仍可返回刚才的版本。基础表单保存时保留最新高级片段。导出仅使用校验后的结构，不含编辑注释、节点密码和完整核心配置；桌面选择保存位置，移动保存应用文档目录，取消不报告成功。

## 验证范围

- Dart：转换、错误脱敏、重复字段/边界限制、旧偏好兼容；校验拒绝保留会话、重连拒绝恢复原目标及 TUN/模式、磁盘失败恢复、陈旧确认拒绝、旧表单保留片段。
- SQLite：真实触发器令历史写入失败，确认当前写入一并回滚；关闭并重开核对两版配置。
- 组件：校验/确认/取消、恢复、导出结构化内容、光标不使校验失效、编辑/离开取消、320/393 宽大字与左上角返回。
- Go：锁定真实核心完整字段检查、受控监听/认证/模式/TUN 合并；本机 DNS 查询、HTTP 直连/代理/拒绝、运行中模式切换；无效配置不打断会话。

本机 fixture 只证明配置和核心路径，不代表服务商可达性。移动界面具备编辑和交互布局，但真实校验仍依赖尚未接入的移动核心服务，不返回虚假成功。不支持完整 Clash/sing-box 配置、脚本、provider、远程规则集或自定义出站。

## 本次实际结果

Flutter 全量 266 项通过；取消竞态覆盖应用过程中主动断开，以及写入失败前用户断开，均不复活会话。之后对紧凑编辑框的调整通过设置组件 12 项回归。211 个 Dart 文件格式检查和最新静态分析通过。Go 全量 92 项通过（含子用例），3 项需要显式启用系统代理的用例跳过，gofmt / go vet 通过；真实核心测试显式设置了锁定核心路径。

`app/integration_test/windows_advanced_config_test.dart` 使用真实 Windows Flutter / Go / sing-box、临时 SQLite、本机 UDP DNS 和 HTTP 源站，验证：

- 无效片段、独立校验、取消应用确认均保留原 sessionId。
- YAML / JSON 使用真实系统保存对话框导出，文件读回解析后与已校验片段一致；导出不重连。
- 在线应用保留原活动 A，节点页新选 B 不影响当前目标；源站实际完成 3 次传输，覆盖解析器实际收到查询，reject 规则阻止请求。
- 恢复上一版后请求恢复正常，关闭并重开数据库后当前/历史配置一致。

回执为 [windows-evidence.json](advanced-config/windows-evidence.json)，实窗截图为 [editor-native.png](advanced-config/editor-native.png)，日志为 `build/advanced-native.log`。普通网络设置原生回归再次通过，见 `build/advanced-settings-native-regression.log`。TUN TCP、UDP 与 DNS 小回归通过，网卡、路由、系统 DNS 和代理回到原摘要，见 [tun-regression.json](advanced-config/tun-regression.json)。未操作 FlClashHelperService，也未使用用户节点或订阅测试本轮配置功能。

## Figma 与布局

实时读取 RainLink 桌面高级配置 `59:47463`，参考截图为 `reference/advanced-desktop-20261017.png` 和 `reference/advanced-mobile-20261017.png`。保留六分类、左上返回、格式切换、单编辑卡及校验/应用；新增恢复、清除和导出放在「⋯」，支持范围置于卡片下方。返回、确认、更多图标重新从 Figma 原生导出，逐字节匹配运行资产，哈希见 [icons.json](advanced-config/icons.json)。

设置视觉集成现在生成 80 张 fixture 截图，覆盖六分类和高级编辑/校验状态：1440×900、960×640、393×852、320×640，深浅两主题；320 宽叠加 1.3 倍字号，移动额外模拟 280 高键盘占位。已检查紧凑桌面、移动深浅色及窄屏大字截图，没有布局溢出。960 小窗口限制代码区域高度，长配置在编辑框内部滚动，主标题和操作保持单页可见；大字及键盘场景可滚动访问操作。截图在 `settings/settings-advanced-*-fixture.png`，键盘占位和移动渲染不代表真实移动系统服务或真机键盘验收。

## Release 交付

最新 Windows x64 Release 已实际启动，进入核心引擎的高级配置，使用随包宿主和核心完成独立校验，再通过原生关闭按钮正常退出。实窗为 [release-editor.png](advanced-config/release-editor.png) 和 [release-validated.png](advanced-config/release-validated.png)。查看期间保持未连接，未应用草稿；启动前后用户数据库、开机启动和系统代理摘要一致，68 个节点、1 个分组、4 项偏好保持不变，SQLite 完整性为 ok，应用和核心无残留进程。回执为 [release-evidence.json](advanced-config/release-evidence.json)。

预览包：`build/RainLink-windows-x64-advanced-preview.zip`，41,148,832 字节；SHA-256 为 `4baf86da0e0a6598ab16ad4676a0b6f37fa757083ef0b1c1a7e41fe63f763ee3`。已验证 Release 引擎、应用/AOT/宿主/固定核心、图标资产、许可和核心源码、ZIP CRC 及全部 75 个文件；包内没有用户数据库。摘要见 [advanced-config-build.json](advanced-config-build.json)，`desktop-build.json` 同步指向此最新预览，旧 TUN 包与验收不覆盖。

解压到新文件夹后运行 `rainlink.exe`，保留完整目录；入口是「设置 → 核心引擎 → 高级配置」。默认空片段沿用原界面设置，无需为普通节点或订阅填写代码。密度选项已在后续接入，见 [密度验收](density.md)，最新包以 `desktop-build.json` 为准；本页保留高级配置阶段的包及证据。全产品仍有在线更新、订阅到期通知、签名安装和其余平台原生服务等工作，完整状态见 [实现清单](../IMPLEMENTATION_STATUS.md)。
