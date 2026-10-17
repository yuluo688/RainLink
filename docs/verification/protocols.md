# 八协议、VMess / TUIC 与添加弹窗验收

2026-10-16，Windows，sing-box 1.12.25-rainlink.1，Flutter 3.27.4。

## 实现

节点表单和订阅解析支持 HTTP / HTTPS、SOCKS5、Shadowsocks、VLESS、VMess、Trojan、Hysteria2、TUIC v5。八种是协议类别，HTTPS 是 HTTP 的 TLS 选项。新增协议与已有节点复用选择、分组、规则、代理链和会话冻结机制；保存仅改变数据和选择，连接仍在概览。

VMess 支持 Clash YAML/JSON `proxies`、v2rayN Base64 JSON 分享链接及 UUID authority 分享链接。支持 `auto`、`none`、`zero`、`aes-128-gcm`、`chacha20-poly1305`，Alter ID 0–65535，TCP / WebSocket / gRPC，TLS / SNI / ALPN / 指纹，global padding、authenticated length、默认 / xudp / packetaddr UDP 编码。Alter ID 0 使用 AEAD；非零保留服务商旧协议语义。旧 `aes-128-ctr` 虽仍出现在上游配置文档，锁定核心实际拒绝它，导入和表单明确排除；KCP、HTTP 伪装和未实现扩展不静默降级。

TUIC 仅支持 v5，UUID 和密码独立保存到已有加密凭据 username / password 中，密码允许为空。支持 Clash、`tuic://UUID:password@server:port`；QUIC 与 TLS 固定启用，提供 cubic / new_reno / bbr、原生 UDP / QUIC 流 / UDP over Stream、心跳（毫秒）、禁用 SNI、可选 0-RTT（默认关闭）和证书 SHA-256 指纹。UDP over Stream 需要服务端兼容，编译时与 udp_relay_mode 互斥。证书指纹始终校验，不能由 insecure 绕过。v4 token、IP 覆盖及未实现的客户端证书、QUIC 扩展明确拒绝。

仅公开选项写入 NodeOptions JSON，UUID、密码不会放进公开 options。旧记录缺失新增选项时恢复默认值，无 schema 迁移，数据库仍为 4。手动编辑留空保留同协议的旧密文，更换协议必须提供相应凭据。订阅刷新保留稳定 ID、选择及不变节点修订。

Windows TUIC 入口沿用 Hysteria2 的物理网卡和 Fake-IP 上游解析策略；后续链跳点仍必须经过前一跳，不绑定本地网卡。HTTP 后续遇到 TUIC / Hysteria2 的 UDP 需求时，在编排和 Host 两层明确拒绝。

## 添加弹窗

从实时 Figma `2:20702` 核对 520 px 宽度、24 px 内边距、16 px 圆角、分段选择和底部主按钮，窄屏按可用空间缩小并滚动正文，底部操作始终保留。订阅支持粘贴按钮；只填草稿，过长内容拒绝，关闭后的异步结果不再写入。自动更新选项随节点、分组一起事务提交，刷新保留该选项；默认周期来自服务商，缺失时 24 小时，仅在应用运行时检查。

本模块使用的复制、关闭、确认、下载、向下 5 个 SVG 从当前 Figma 原生重新导出，与运行资产逐字节相同，见 `protocols/icon-verification.json`。引用画面是 `protocols/figma-add.png`。协议表单增加了当前真实核心所需字段，整款产品的全页面像素审核尚未完成。

## 已验证

本轮最终格式检查覆盖 162 个 Dart 文件，`flutter analyze` 无问题；Flutter 全量 194 项通过，Go 全量 75 项通过、3 项需显式修改系统代理的测试跳过，`go vet` 通过。两个无测试包的 skip 不计入测试项。Windows 最终导入/连接集成和视觉集成均成功；视觉覆盖 960×640 / 393×852、深浅色、两个协议的普通/高级表单及订阅弹窗，共 20 张截图，已查看。

- Flutter 业务回归：分享链接、混合八协议订阅、参数冲突、v4/旧加密拒绝、凭据不进入 options、密文编辑保留、刷新稳定 ID、旧字段默认值、链路 UDP 约束。
- 表单回归：VMess 桌面保存、TUIC 移动 1.3 倍字体保存、无效 UUID 保留表单、剪贴板只填草稿、自动更新关闭落库、关闭后迟到剪贴板结果不提交。
- Go 实际核心转发：VMess auto / AES / ChaCha、旧 Alter ID、WebSocket/TLS、gRPC/TLS；TUIC 三种拥塞控制。错误认证均不达源站；TUIC 错误 UUID、自签证书和错误证书指纹被拒绝，正确指纹成功。
- 实际 UDP：TUIC native / quic / UDP over Stream；VMess 默认 / xudp / packetaddr。测试通过 SOCKS5 UDP associate → RainLink 混合入站 → 协议上游 → UDP 回显源站，校对完整数据包。
- 实际混合代理链：VMess → TUIC 和 TUIC → VMess，均验证 HTTP 负载、UDP 回显，并从入口核心日志确认其向下一跳监听器转发。
- Windows 独立临时数据库：真实窗口手动添加 VMess（Alter ID 64）、URL 导入指纹校验的 TUIC、点选后从概览连接、两次实际 HTTP 负载、DPAPI 密文检查；不更改系统代理或用户数据库。

证据：`build/vmess-tuic-flutter-test.jsonl`、`build/vmess-tuic-go-test.jsonl`、`build/vmess-tuic-windows-integration.log`、`build/vmess-tuic-mixed-chain.log`、`build/vmess-tuic-visual-integration.log`，以及 `protocols/windows-evidence.json`、`protocols/*-fixture.png`。视觉样例是隔离排版数据；移动布局截图不代表 Android / iOS 网络服务已接通。

边界：VMess / TUIC 本轮为本机真实核心互通与负面验证，未逐一连接远程服务商；Hysteria2 既有机场证据见 `routing/hysteria2-remote.json`。Hysteria 1、TUIC v4、TUN、移动后台网络服务、macOS/Linux 宿主和剩余业务仍按实现清单推进。

## Windows 预览包

`build/RainLink-windows-x64-protocols-preview.zip`，41,306,791 字节，SHA-256：`c59b7e1c1f854c1de896151530c6bedad97d17fd6b1c92560862c999cce67bc7`。Release 引擎与 SDK 对应缓存一致，Host / 核心摘要见 `protocols-build.json`。包中附核心许可证与对应源码。

已启动实际 Release，核验默认紧凑概览完整显示、添加协议下拉包含八协议、订阅粘贴与自动更新界面，随后正常关闭；未向用户库写入测试节点或启用系统代理。实窗截图为 `protocols/release-overview.png`、`release-add.png`、`release-protocols.png`、`release-subscription.png`。
