# Android 代理链、规则与在线配置验收

日期：2026-10-17。设备为隔离的 `RainLink_QA`，Android 16 / API 36 x86_64、2 GB 内存。使用真实 Flutter 移动界面、Android 桥接、Keystore、SQLite 和嵌入式 libbox；代理及目标服务均在模拟器本机。没有导入远程订阅，也不代表远程多协议链已经验收。

[结果](android/flutter-configuration-evidence.json)记录 9 次成功响应，目标服务器恰好收到 9 次请求。入口为 `app/integration_test/android_configuration_test.dart`，不是普通预览 APK 的入口。

## 已验证的流程

1. 在移动端可视化编排界面选择两个 HTTP 跳点并保存；原生核心先校验，SQLite 保存成功后只选中代理链，尚未建立连接。
2. 回到概览点击连接，确认实际系统隧道及活动代理链身份；请求依次经过 `A → B → 目标`。
3. 将保存的链改为 `B → A`，再选择另一单节点；已经建立的会话仍按原来的 `A → B` 转发。
4. 在线应用高级配置，拒绝目标 IP 和端口。实际请求无法取得目标响应，目标请求计数保持不变。新会话保留原活动目标、版本、模式及两跳绑定，配置与上一版通过同一数据库事务保存。
5. 恢复空高级配置后，原双跳路径重新完成传输，上一版配置仍可读取。
6. 占用本地监听端口，触发核心真实启动失败；应用报告失败并恢复原连接，原双跳路径继续可用。
7. 断开再连接修改后的链，实际路径变为 `B → A → 目标`。
8. 将规则兜底出站设为代理链，同时连接单节点 A。规则模式实际走 `B → A`，全局模式走 A，直连模式绕过两跳；切回规则模式后重新走链。
9. 最后断开，原生快照确认没有活动会话，Flutter 没有遗留框架异常。

## 路径核对

核心会同时发起后台出口和延迟探测。验收请求带有独立标记，每个本机 CONNECT fixture 记录该请求在自己的隧道中转发的目标。每一跳必须恰好出现一次；全局和直连模式还核对不应经过的跳点没有该请求，不能用后台连接数量代替实际路径。

共享 fixture 的回归测试另外覆盖并发背景隧道、分片请求头及完整的 2 MB 响应。403 项共享 Flutter 测试全部通过。

前几轮保留了失败记录：一次路径断言混入后台探测，另一轮软件渲染模拟器卡顿导致原生保存超时。重新启动同一 QA AVD、改用宿主 GPU 后，系统截图约 1 秒返回，完整配置测试约 16 秒通过；网络请求超时和业务断言均未放宽。这些时长只用于诊断该模拟器，不构成产品性能验收。

## 网络切换

[原生结果](android/native-evidence.json)与[切网输出](android/instrumentation-network-handover.txt)另记录同一会话及同一个系统隧道的四个阶段：

| 阶段 | 实际条件 | 请求结果 |
| --- | --- | --- |
| Wi-Fi | 唯一可用物理网络为 Wi-Fi | 独立 shell UID 经系统隧道完成认证代理传输 |
| 蜂窝 | 关闭 Wi-Fi，唯一物理网络为蜂窝 | 新请求继续完成传输 |
| 断网 | Wi-Fi、蜂窝均关闭，物理网络列表为空 | 请求无法取得目标响应，原隧道保持 |
| Wi-Fi 恢复 | 恢复 Wi-Fi 并重新连接虚拟 AP | 原会话、原系统隧道恢复传输，无需重连 |

随后再次断网并手动断开，再恢复 Wi-Fi。应用保持空闲，原恢复请求已释放，系统没有迟到创建的隧道。三次成功响应分别发生在 Wi-Fi、蜂窝和恢复后的 Wi-Fi；记录还包含每阶段实际网络能力。

该测试仅接受命名 QA AVD，并明确连接其虚拟 `AndroidWifi` 网络，避免公网连通性检查失败导致模拟器停用自动加入。结束后回读 Wi-Fi、蜂窝开关，确认与测试前一致。连同原有网络、文档及通知验证，共 10 项原生测试在五个独立进程中通过。

这证明模拟器的系统网络切换和本机目标传输；真机的运营商、热点、漫游及厂商后台限制仍需验证。

## 复现

先按 [Android 验收](android.md)构建普通应用与测试 APK，再从仓库根目录执行：

```powershell
$env:ORG_GRADLE_PROJECT_useMavenMirror='true'
python tools/verify_android.py --serial emulator-5580 --ui --ui-suite configuration --flutter-root $env:FLUTTER_ROOT
# 恢复普通入口后，运行完整十项原生验证及切网。
python tools/build_android.py --java-home $env:JAVA_HOME --use-maven-mirror
python tools/verify_android.py --serial emulator-5580 --handover
```

工具只接受名称为 `RainLink_QA` 的 AVD，预先授予测试权限，不能替代系统授权弹窗验收。`flutter drive` 使用临时测试入口；结束后必须重新运行 `tools/build_android.py` 恢复 `lib/main.dart`，然后进行原生和包检查。

本次覆盖本机 HTTP 双跳和受控高级片段；远程多协议链、代理链独立测速在 Android 上的取消及故障定位、真机授权和长期运行仍需继续验收。
