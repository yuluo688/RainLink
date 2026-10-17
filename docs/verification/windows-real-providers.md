# Windows 真实订阅与 HTTP 节点验证

2026-10-16，Windows x64，Flutter 3.27.4 / Dart 3.6.2、sing-box 1.12.25。本轮使用用户授权的真实订阅和两个认证 HTTP 节点；没有把订阅地址、账号、密码写入本文或代码。

## 结论

完成真实流量验证，并修复了订阅内容协商的问题。**整轮实网验收为部分通过**：曾成功连接的线路在后续复测中出现超时、握手中断及 HTTP 400，不能将一次成功当作稳定性验收。

| 项目 | 实际结果 |
| --- | --- |
| HTTP 节点 1 | 首轮独立 HTTP CONNECT 和 RainLink 均成功；HTTPS 出口 `195.40.63.44`，国家 GB。RainLink 请求耗时 1908 ms，真实上传 / 下载计数均大于零 |
| HTTP 节点 2 | 首轮独立 HTTP CONNECT 和 RainLink 均成功；HTTPS 出口 `138.226.63.46`，国家 US。RainLink 请求耗时 965 ms，真实上传 / 下载计数均大于零 |
| HTTP 复测 | 独立测试也出现超时、HTTP 400、远端断开；RainLink 相应出现超时或握手中断。最后一轮两个节点均未通过，不能报告当前稳定可用 |
| 订阅识别 | 修复前服务商返回 3 个“不支持您的代理软件”等本机占位条目；修复后返回 71 项：52 条 VLESS、16 条 Hysteria 2、3 个用量 / 到期 / 重置提示 |
| 有效导入 | 最终导入 52 条 VLESS，自动生成订阅分组；跳过 16 条当前不支持的 Hysteria 2 以及 3 个提示条目。普通本机代理仍允许导入 |
| 用量 / 到期 | 真实响应头提供用量和总量；观测到约 25.5 GiB / 1000 GiB，到期 `2029-12-17 18:15:35 +08:00`。数值会随实际使用变化 |
| 刷新 / 选择 | 一轮真实刷新成功，节点 ID 与选择保持、两个手动节点仍在未分组；另一次真实刷新失败，错误被保留。失败回滚还由仓库回归测试覆盖 |
| VLESS 转发 | 日本、新加坡、美国共 5 条实际线路曾成功完成 HTTPS 请求并记录出口 / 流量；最后一轮抽测 6 条，其中美国 WebSocket/TLS 成功，其余 5 条 Reality/Vision 连接失败 |
| 清理 | 每轮断开均关闭测试监听器；测试前后 Windows 系统代理五项注册表值完全一致。没有启用 RainLink 系统代理或 TUN |

测试环境原先运行着 FlClash TUN，DNS 返回 Fake-IP 地址。本轮保留了该环境，没有停止其他网络工具。独立 HTTP 测试失败表明对应故障可以发生在 RainLink 之外；现有证据不能进一步区分服务商故障与当前网络路径问题。

出口国家来自公开 IP 数据源。新加坡线路曾出现 Cloudflare 为 SG、宿主使用的 IP 数据库为 US，IP 地址相同。国家图标表示 IP 数据库归属，不等于已经验证的物理位置。

## 本轮修复

- 订阅请求使用 `clash.meta RainLink/0.1` 协商 Meta 兼容 YAML，同时保留 RainLink 标识。此前只声明 Clash 兼容时，该服务商返回不支持客户端的提示节点。
- 仅过滤同时满足“指向本机”及“名称明确为服务商提示”的条目，包括软件不支持、官网、剩余流量、到期和下次重置。全部为提示条目时明确报错，不提交空或虚假的线路列表；正常本机节点和名称相似的远端节点保留。
- 分组详情的跳过说明覆盖不支持、无效和提示条目。

新增回归先复现了旧标识导入 `127.0.0.1` 占位条目的错误，再验证新行为。Flutter 静态检查通过；112 项单元 / 组件测试通过。没有修改原生转发配置或核心版本。

## 私密输入与复现

`tools/verify_remote.py` 使用隐藏输入接收 JSON，经私有 stdin 交给 Dart 校验脚本。脚本复用应用的 HTTP 拉取器、解析器、Drift 仓库、DPAPI、宿主通信和实际核心；数据库使用内存实例。输出仅含匿名编号、协议、少量已清理的中文名称、出口、计时、计数和结果。输入不进入 argv、Dart 编译参数、源码、数据库文件或截图。

```powershell
python tools/verify_remote.py --dart '你的 Dart SDK/bin/dart.exe' --output build/remote-verification.json
```

在隐藏提示中提供以下结构，将值换成自己的数据，不要把真实凭据写进命令历史或文件：

```json
{
  "subscription": "https://provider.example.test/subscription",
  "proxies": [
    {"server": "proxy.example.test", "port": 8080, "username": "YOUR_USER", "password": "YOUR_PASSWORD"}
  ],
  "sampleLimit": 6
}
```

可省略订阅或将 `proxies` 置空。`sampleLimit` 为 1–12；可设 `subscriptionViaManual` 为手动节点的零起始索引，通过该节点拉取和刷新订阅，仍不修改系统代理。没有该字段时使用当前系统网络。连接、流量或刷新失败会输出失败结果并返回非零退出码；整体执行有超时限制。此工具需要已经构建的 Windows 宿主 / 核心和 SQLite DLL，不进入应用包。

原始脱敏记录保存在忽略的 `build` 目录：

- `remote-verification.json`：首轮两个 HTTP 成功及旧标识问题。
- `subscription-provider-proxied-diagnostic.json`：旧标识与 Meta 标识的服务商响应对比；只保留数量、协议和已清理的提示，没有响应正文。
- `remote-verification-fixed.json`：真实刷新成功、5 条 VLESS 转发成功，随后补齐重置提示过滤。
- `remote-verification-final.json`：最终 52 条有效导入，6 条 VLESS 复测中的成功及失败。
- `remote-http-retest.json`：最后一次独立 HTTP 与 RainLink 对照，结果均失败。

这些记录来自不同时间和网络状态，不能混合汇总为“全部通过”。本轮未导入用户的持久数据库，也未做移动网络接管、Hysteria 2、全量 52 条线路测速或长时间稳定性测试。

## 构建

更新的完整 Windows 包：`build/RainLink-windows-x64-provider-tested-preview.zip`。解压后运行 `RainLink/rainlink.exe`，保留同目录文件。构建校验、CRC、SHA-256 与本轮发布启动证据见 [构建清单](windows-real-providers-build.json)。本轮实网使用共享业务 / 数据 / 宿主链路，没有通过自动化界面输入真实秘密；真实界面流程沿用此前本地夹具的 Windows 集成测试记录。
