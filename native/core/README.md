# RainLink 的 sing-box 兼容扩展

基于上游 `github.com/sagernet/sing-box@v1.12.25`，增加标准 TLS 的 `rainlink_certificate_sha256` 配置及校验，以及实际出站 / 应用的累计流量接口；Linux 桌面核心另有受控 TUN 资源扩展。Clash Hysteria2 的 `fingerprint` 是完整 DER 证书的 SHA-256；不能映射为 uTLS 浏览器指纹，也不能映射为 SPKI 公钥摘要。

叶证书指纹匹配时直接信任该证书；中间或根证书匹配时，还必须验证叶证书链、用途、有效期与服务名称。指纹有值时，`insecure` 不会跳过指纹校验。这与 Mihomo 的证书指纹语义一致。无指纹时，完全沿用上游 TLS 行为。RainLink 宿主只对 Hysteria2 开放此选项。

`tools/setup_core.py` 验证 Go 模块校验值与修改的上游文件 SHA-256，在 `build/core-source` 创建构建副本，以 Go overlay 注入 TLS、累计统计和新增源文件；不修改模块缓存。`tools/core.lock.json` 固定 Go 1.25.5、构建标签及各平台最终二进制 SHA-256。Windows / macOS / Android 使用 `1.12.25-rainlink.3`；Linux 托管 TUN 版本为 `1.12.25-rainlink.4`。

`GET /rainlink/traffic` 位于现有 Clash API 认证组内，返回 version=1、独立 epoch、上下行累计总数、limited 和按实际 outbound / 进程 basename 或 Android package 分区的 rows。每条 TCP / UDP 流创建时固定计数器指针，字节路径只做原子加法；切换模式不会重新归属已有流，流关闭后也不会丢掉累计计数。此计数独立于 Clash 的统计重置，新核心实例才更换 epoch。

最多保留 2,048 个来源组合、127 个已识别应用及一个未知溢出计数器。超限不丢总字节，无法识别或超限的维度明确记为未知。接口不会返回目标地址、PID、用户名或完整进程路径。每份响应的总数来自同次读取的行之和，宿主再分别聚合出站与应用，两种排行各自守恒，不能相加。应用识别由宿主配置 `route.find_process=true` 请求，平台权限或系统 API 不可用时仍保留为未知。突然退出前尚未持久采集的增量无法恢复。

Linux 构建使用独立源码副本，以及相对路径替换的 `sing-tun v0.7.13` / 固定 netlink 模块；两者的模块和改动文件也锁定校验值。新增的 `rainlink_managed=true` 只用于权限辅助进程编译的固定双栈、`auto_route` / `strict_route` 配置，不开放任意路由或自动重定向。启动前检查名字、表、完整规则区间及 GOTO 引用，使用 `IFF_TUN_EXCL` 创建独占设备；生成的 16 条规则带协议编号 242。协议编号提供内核删除过滤条件，不能代替完整规则身份和资源租约。

托管模式不运行上游的区间删规则、按名字清理路由 / 地址或 `resolvectl`；正常退出仅关闭自己持有的独占 TUN 文件句柄。所有规则（含部分启动残留）由资源守护层在核心退出后精确恢复，动态路由更新要求重连。启动 / 强杀恢复记录必须先绑定核心，再释放 stdin 配置。没有权限流程和恢复进程时不得单独开启托管 TUN；未设置该选项继续保留上游行为。此扩展只在 Linux 桌面源码变体启用，Windows 与 Android 使用原 TLS 扩展变体。

正常构建：`python tools/setup_core.py`。审查本地扩展修改后，使用 `python tools/setup_core.py --update-lock` 重建并更新二进制校验值。默认构建绝不自动接受新的校验值。上游源码更新时必须重新审查插入位置和指纹语义。

测试包含 TLS、认证 API、并发计数、容量上限、隐私与累计守恒测试，以及宿主驱动真实 QUIC / Salamander 服务端的传输测试：正确认证和证书指纹可传输，错误密码、混淆密码和指纹均拒绝；无指纹的未受信任证书仍拒绝。流量集成覆盖模式切换中的已有 TCP、超过上游结束连接缓存容量的短连接及真实 UDP。真实机场可达性需单独测试。

扩展与修改后的 sing-box 按 GPL-3.0-or-later 提供。上游许可证随运行包分发；构建同时生成 `sing-box-source.zip`，包含相应源码、Linux 本地替换模块及其许可证和复现说明。Linux TUN 扩展测试交叉编译到 `build/core-tests/<平台>/sing-tun.test`；交叉编译成功不代表已经执行，实际 Linux 运行由隔离网络 QA 记录。

参考：[sing-box v1.12.25](https://github.com/SagerNet/sing-box/tree/v1.12.25)、[Mihomo 指纹验证](https://github.com/MetaCubeX/mihomo/blob/Meta/component/ca/fingerprint.go)。
