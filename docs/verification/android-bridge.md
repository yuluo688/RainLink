# Android 桥接恢复与内存对齐修复

2026-10-17，在隔离的 Android 16 x86_64 模拟器验收中发现并修复以下问题。网络和凭据均来自本机 fixture。

## 会话恢复

Go 会省略空的 `runtimeSettings.advanced`；Flutter 默认将其写成 `{}`。原来直接比较原始 JSON 字段，会在有效后台会话恢复时误报配置不一致并主动断开。

`AndroidCoreGateway` 现在先通过 `CoreRuntimeSettings.fromJson` 严格解析回执，再比较规范化的设置。省略、空字符串和空对象等价；端口、DNS 类型和地址、引导解析、IPv6、日志级别及实际高级配置仍须匹配。目标、模式、规则修订及出站绑定的校验继续保留。新增回归同时覆盖等价空值与真正不匹配时断开。

核心启动还会通过 `/configs` 设置并回读模式，确认实际生效以后才返回连接成功。

## 启动失败后的清理与就绪

固定 sing-box 的 `Box.Start` 在启动失败时会自行关闭，之后 `Box.Close` 返回精确的 `os.ErrClosed`。原先外层将它记为永久清理失败，取消后再次断开或连接都会失败。现在仅将该精确哨兵视为幂等关闭；其他错误及组合清理错误仍报告失败，不将未知清理结果伪装成成功。

原生回归连续三轮占用真实本地代理端口，触发 libbox 启动失败，确认返回空闲并释放恢复请求，再重连并验证独立 UID 的真实传输。连接成功还须等待 Android 登记与核心实际接口名相同的系统隧道；等待有超时，并检查当前操作是否已取消。

恢复测试的上游代理固定延迟握手 1.5 秒，避免只覆盖本机瞬时握手。测试请求由测试 APK 内的纯 Java Socket 客户端通过 `app_process` 以 shell UID 发出，写完请求后保持写端直到响应完成，并设置连接、读取超时和响应大小上限；它不进入普通应用 APK。脚本摘要与设备上的实际文件一致，记录在原生机器结果中。

此前 `nc` 的生产者管道在一秒后结束，慢握手尚未完成时即半关闭请求，造成测试客户端自身的假失败。相同 1.5 秒握手条件下，[旧客户端首轮失败](android/request-lifetime-before.txt)，保持写端的[新客户端连续三轮通过](android/request-lifetime-after.txt)，另有[计数证据](android/request-lifetime-evidence.json)。该修正没有跳过传输或放宽恢复断言。

## 桥接崩溃

[修复前诊断](android/bridge-crash-before.txt) 指向 `_cgoexp_*_proxymobile_Runtime_Snapshot`：C 生成的 packed 回调参数帧未保证指针大小对齐，返回结构含指针时，Go 的内存写屏障触发 `bulkBarrierPreWrite: unaligned arguments`。默认内存条件下间歇出现，低内存反复传输时可复现。

移动构建现在从固定 Go 1.25.5 源码构建局部 cgo 生成器：只给导出回调的局部帧增加 `__aligned__(p.PtrSize)`，保留所有字段偏移。`-toolexec` 分发器仅替换移动构建的 cgo 工具，并返回与二进制摘要绑定的构建 ID，避免复用旧 cgo 产物。安装的 Go、桌面构建及 Go 运行时均保持原版。

- 固定源码和 SHA：`tools/mobile-core.lock.json`。
- 补丁和局部工具构建：`tools/mobile_cgo_alignment.py`。
- 工具分发器：`tools/mobile_cgo_tool/main.go`。
- 构建证据记录原始源码、补丁后源码、分发器源码和工具二进制摘要，附在原生及 APK 验收记录的 `coreBuild.cgo` 中。

用于定位的运行时诊断仅存在于隔离的临时构建；最终核心重新从正常构建脚本生成，不包含 `QA fault arguments` 等诊断插桩。

## 回归范围

原生验收的持续传输测试在 Activity 重建、原会话恢复和按原快照重连之后启用 libbox 低内存模式，再完成 12 轮真实 TUN 传输与快照读取；finally 恢复内存策略并断开。修复后普通核心已连续两轮通过这三项原生测试。最终交付摘要和最近一次结果以 [Android 原生验收](android.md)、[机器记录](android/native-evidence.json)为准。

这项结果证明该模拟器上的回归，不替代 arm64 真机、长期运行或厂商后台限制验收。
