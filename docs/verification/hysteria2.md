# Hysteria2 导入与连接验证

2026-10-16，Windows x64，Flutter 3.27.4 / Dart 3.6.2、Go 1.25.5，sing-box 1.12.25-rainlink.1。

本页保留首次支持补齐时的记录。后续已取得真实机场 HTTPS、出口与流量成功记录，新增上游网卡和 Fake-IP 处理；最新结论及仍存在的波动见 [真实网络续验](hysteria2-network.md)。

## 原因与改动

旧版 RainLink 的协议枚举、订阅解析与宿主白名单没有 Hysteria2，订阅中的这些条目被跳过。现在支持 Clash `type: hysteria2` / `hy2`、`hy2://` / `hysteria2://` 分享链接以及手动添加。QUIC 和 TLS 自动启用，支持认证、SNI、ALPN、Salamander、带宽和端口跳跃；Clash `ports` 与兼容别名 `mport` 同时存在时必须一致。

真实订阅的 16 条 Hysteria2 还带有完整证书 SHA-256 指纹。上游 sing-box 1.12.25 没有对应配置入口，因此加入 [小型 TLS 扩展](../../native/core/README.md)，保留 Mihomo 的叶证书和中间证书指纹语义。错误指纹不能被「跳过证书验证」绕过。它与 uTLS 的浏览器指纹分开存储；没有降低真实节点的校验要求。

认证和混淆密码一起用 Windows DPAPI 加密，公开 options 不包含密码。旧密文兼容；修改订阅时保留同一节点 ID 和当前选择。SQLite schema 仍为 3，无需破坏性迁移。

## 自动和本地核心测试

- Dart format：118 个文件，无改动；Flutter analyze 无问题；138 项 Flutter 测试通过。
- Go format、vet 和完整宿主测试通过；真实核心参与验证。3 项需要显式开启的系统代理写入测试本轮跳过。
- 真正的 sing-box Hysteria2 QUIC / Salamander 服务端收到并返回 HTTP 负载；错误认证、错误混淆密码和错误证书指纹被拒绝。未提供指纹且未开启跳过验证时，不信任自签名证书。
- 端口跳跃配置通过实际核心 `check`，单个端口转换为核心要求的范围格式。
- 测试覆盖 Clash 订阅、URI 别名、编码认证、提供商指纹与重复端口别名、非法输入、刷新与选择保持、秘密轮换和移动窄屏编辑弹窗。
- 核心源码、修改位置、Go 版本、构建标签及产物校验值均固定。随包源码 ZIP 重新构建得到相同二进制 SHA-256。

## 真实订阅与外网边界

用户已授权使用原有订阅。测试只在私有内存或加密数据库中处理地址和密码；没有把它们写入命令行、代码、日志或本文。

先在内存数据库验证真实订阅导入及刷新：得到 **68 个节点 = 52 个 VLESS + 16 个 Hysteria2**；仅跳过 3 条服务商提示。订阅自动分组、用量、到期时间正常；刷新保持节点 ID 和选择。

随后在重新构建的 Windows Release 中，通过「分组 → ⋯ → 更新订阅」更新用户原数据库。实际保存 68 个节点，原有 52 个节点 ID、当前选择和浅色主题保留。未添加任何额外测试节点；当前仍未连接，系统代理关闭。取消手动添加的验证弹窗后，停留在节点页的 `Hysteria2` 搜索结果。

4 条 Hysteria2 外网抽测均未成功完成 HTTPS 传输。核心就绪与外网可用性分开判断，报告没有将核心启动成功计为连接成功。对其中一条使用**虚构认证密码**进一步诊断，固定端口及端口跳跃均报告 QUIC `timeout / no recent network activity`。因此本轮没有证明真实机场 Hysteria2 的连通性，也不能据此认定是服务商故障。系统代理的所有原值保持一致。第一次订阅请求也曾超时，重试及最终界面刷新成功。

原始脱敏证据：[外网抽测](hysteria2-real-provider.json)、[无真实认证的 QUIC 诊断](hysteria2-connectivity-diagnostic.json)、[构建与界面记录](hysteria2-build.json)。

## 实际 Release 截图

- [更新后的原订阅分组](hysteria2-groups-release.png)
- [真实 Hysteria2 节点列表](hysteria2-nodes-release.png)
- [手动添加 Hysteria2](hysteria2-editor-release.png)
- [证书指纹高级选项](hysteria2-editor-advanced-release.png)
- [带宽、端口跳跃与混淆](hysteria2-editor-quic-release.png)

移动端仅验证共用模型、导入逻辑与 Flutter 组件布局；没有在真实手机上验证网络接管。VMess、Hysteria 1、TUIC、TUN 等能力仍不在本轮完成范围内。
