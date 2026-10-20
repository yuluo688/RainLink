# 桌面宿主接口

## 状态协议 1

`rainlink-host status` 返回单次 JSON；退出码 0 表示读取成功。stdout 只写协议，stderr 不向界面转发。桌面 Gateway 将启动和读取限为 20 秒，以容纳 Linux 有界的 10 秒服务检查及核心发现；通用 runner 默认仍为 5 秒。stdout/stderr 各限 64 KiB，失败或销毁时回收子进程。同一 Gateway 只共享正在执行的检查，后续刷新不缓存旧状态。

Windows 下发现旁边可运行的 sing-box 时返回：

```json
{
  "protocolVersion": 1,
  "host": { "version": "0.1.0", "platform": "windows", "arch": "amd64" },
  "core": { "state": "ready", "version": "1.12.25-rainlink.3" },
  "capabilities": { "connect": true, "systemProxy": true, "tun": true }
}
```

没有核心或平台尚未适配时，`core.state` 为 `not_configured`，`core.version` 为 null，能力全部 false。状态检查不会启动会话或修改代理。TUN 能力还要求核心 SHA-256 与宿主锁定版本一致。

Linux amd64 在找到旁置核心时返回 `core.state=ready`、`connect=true`。`tun` 仅在核心可信、已安装权限服务与当前构建一致、socket 已启用且活动时为 true；检查只读，不请求授权。安装/卸载/失败/取消回读后刷新能力，刷新中不沿用旧开关状态；完整产品连接仍待验收，见[暂停检查点](verification/linux-tun-product.md)。`systemProxy` 根据实际环境返回：GNOME（包含 `ubuntu:GNOME`）需要 dconf、可写代理 schema 和匹配配置；KDE 需要旁置且通过检查的 Qt6 / KF6 ConfigCore 辅助程序。两者均需可用会话总线与 pidfd 监控，未知或无法验证的环境为 false。凭据依赖已安装且可解锁的 Secret Service，不支持的接管请求不会启动核心或修改系统。KDE 范围见[KDE 系统代理](verification/linux-kde-proxy.md)。

macOS 使用 `host.platform=darwin`，当前只允许 `connect=true, systemProxy=false, tun=false` 的就绪响应。代码使用同一私有会话与旁置核心，凭据通过旁置 `rainlink-keychain` 的私有管道请求 Security.framework；不会把节点密码或主密钥放入进程参数。Go 双架构交叉编译和跨平台回归已通过，Swift/Keychain/系统代理及原生运行仍需 Mac 验收，见[基础接入](verification/macos-foundation.md)。本地签名改变核心文件字节时，构建器先核对原始源码锁，再将签名后摘要在链接时固定到宿主；运行时没有摘要覆盖入口。

## 桌面会话协议 2

Flutter 启动自己拥有的 `rainlink-host serve`，通过继承的 stdin / stdout 交换逐行 UTF-8 JSON。GUI 与宿主之间没有公开控制端口或任意命令入口；核心路径固定为宿主旁的 `sing-box.exe`（Windows）或 `sing-box`（Linux/macOS）。macOS `.app` 的宿主、核心和 Keychain helper 位于 `Contents/MacOS`。私有 stdio 替代开发方案中尚未实现的 Named Pipe 传输。

每条消息限 128 KiB。请求 ID 为正整数；响应回传相同 ID。正常结果为对象或省略，无错误时 UI 才提交状态。公共错误只有脱敏的 `code` 和中文 `message`。普通宿主操作期限 20 秒、Flutter 请求期限 25 秒；连接为管理员授权预留宿主 90 秒、Flutter 95 秒，仍可随时取消。多个 UI 请求可同时等待，stdin 的写入与 flush 按帧串行。

```json
{"id":1,"method":"hello","payload":{}}
{"id":1,"result":{"protocolVersion":2,"coreVersion":"1.12.25-rainlink.3"}}
```

| 方法 | payload | 结果 / 行为 |
| --- | --- | --- |
| hello | 无 | 版本握手；恢复已退出宿主遗留的代理记录 |
| validateRules | revision、rules | 校验并通过 bundled core check 验证受控路由，不替换活动会话；失败保留原配置 |
| protect | id、username、password、可选 obfsPassword | 返回绑定用户和记录 ID 的密文；Windows 用 DPAPI，Linux/macOS 分别用 Secret Service/Keychain 主密钥与 AES-GCM；macOS 原生实现待验收；混淆密码与认证一起加密 |
| reveal | id、cipher | 通过私有会话解密同一 ID 的凭据；仅用于订阅地址读取和更新时复用认证，不提供公开解密端口 |
| connect | node 或 chain、mode、systemProxy、tun、可选 routing / runtimeSettings | 恰好一个主目标；冻结全部出站及网络设置，核心校验、启动、API 就绪、TUN 网卡和双栈路由确认、系统代理回读完成后返回会话快照 |
| snapshot | 无 | 当前会话与核心真实计数；控制 API 失败返回 failed 并保留会话标识以便断开 |
| connections | sessionId、可选 snapshotId / cursor | 获取实际连接的稳定快照，每页最多 32 条；next=-1 表示结束，快照有效期 30 秒 |
| traffic | sessionId | 当前核心周期的累计字节及独立的实际出站、应用归属分区，包含已结束连接；不返回目的地址和完整进程路径 |
| closeConnections | sessionId、connectionId 或 all=true | 校验活动会话；关闭后回读确认目标 ID 消失，不能用旧会话关闭新连接 |
| logs | stream、after | 有界增量脱敏日志；返回宿主流标识、游标、more、dropped 和每批最多 16 条事件 |
| clearLogs | 无 | 清空宿主日志并返回清空时游标；UI 串行提交后清理本地历史 |
| mode | mode | rule / global / direct；应用后回读确认 |
| capture | enabled | 启用或恢复 Windows / GNOME 用户系统代理，回读确认；操作可取消，恢复使用独立期限 |
| probe | 无 | 取消旧探测并启动实际出口和 HTTP 延迟检测 |
| cancel | 无 | 取消正在执行的操作；调用端随后 disconnect 收尾 |
| disconnect | 无 | 先恢复系统代理，再停核心并确认 TUN 已清理；可重复调用 |

`node` 包含 id、name、revision、protocol（http / socks / shadowsocks / vless / vmess / trojan / hysteria2 / tuic）、server、port、tls、credential（密文）、options（公开传输设置）。边界校验拒绝无效地址、端口、协议和不匹配的 TLS / 传输选项。HTTP 可开启 TLS；SOCKS5 固定使用版本 5；Trojan 必须 TLS。VLESS / VMess UUID 和 Shadowsocks / Trojan / Hysteria2 密码保存在加密凭据的 password 字段，TUIC v5 UUID 在 username、密码在 password；SS 支持三种 AEAD 和三种 2022 方法，2022 密钥需通过长度校验。认证不会进入 SQLite 明文、命令行参数、临时配置文件或日志。

`options` 包含 method、serverName、insecure、transport（tcp / ws / grpc / quic）、path、host、serviceName、flow、fingerprint、realityPublicKey、realityShortId、alpn。WS / gRPC 附加传输用于 VLESS / VMess / Trojan；QUIC 用于 Hysteria2 / TUIC v5。Vision 要求 VLESS + TLS + TCP；Reality 要求 VLESS、TLS、有效公钥与 TLS 指纹。由明确白名单编译到 sing-box，不接受任意远程核心配置。订阅 URL 也使用 protect / reveal 绑定独立分组 ID，数据库只存密文和去重摘要。单条凭据最多 4096 字节，密文读取最多 32 KiB。

VMess 增加 vmessSecurity（auto / none / zero / aes-128-gcm / chacha20-poly1305）、alterId（0–65535）、globalPadding、authenticatedLength。packetEncoding（空 / xudp / packetaddr）用于 VMess / VLESS。锁定核心不接受 aes-128-ctr，边界校验和导入明确拒绝。TUIC 仅 v5，固定 QUIC + TLS；增加 congestionControl（cubic / new_reno / bbr）、udpRelayMode（native / quic）、udpOverStream、zeroRttHandshake（默认 false）、heartbeatMillis（默认 10000）、disableSni。udpOverStream 启用时不同时输出 udp_relay_mode；certificateSha256 复用证书摘要机制，不会被 insecure 绕过。v4 token 及未支持扩展明确拒绝。

连接快照包含 phase、sessionId、node（去除凭据）、mode、configRevision、proxyPort、systemProxy、error、可选 telemetry。node 是连接时的快照；编辑或改选不会改变运行中的连接。核心就绪与公网探测分开，核心运行成功不代表上游一定可达。

`connect` 增加可选 `routing: {revision, rules, outbounds}`。规则包含 id、type（DOMAIN / DOMAIN-SUFFIX / IP-CIDR / MATCH）、value、target、enabled；最多 256 条，其中唯一 MATCH 须启用并位于最后。target 为 proxy、direct、reject、node:ID 或 group:ID；独立引用最多 32 个，outbounds 冻结其 key、名称及节点快照。域名按 ASCII / Punycode 校验，不接收 URL 或通配符；IPv4 / IPv6 CIDR 归一化。失效引用阻止连接，停用规则的引用可暂存修复。

Flutter 在同一 SQLite 事务读取规则与分组记忆节点；空组报错，记忆节点已删除时按名称、ID 选择首个节点。Host 校验全部引用、凭据和完整配置后才启动，所有规则出站均保留协议安全选项；Hysteria2 / TUIC 的网卡及加密 DNS 策略逐入口出站应用，后续链跳点仍经前一跳。direct / global 模式位于用户规则之前；自定义规则按保存顺序匹配。旧调用未提供 routing 时保留原局域网直连行为。快照增加 ruleRevision 与 routeBindings（key → id、revision），客户端核对实际应用值。保存规则不会更新活动配置，界面提示断开重连后应用。

客户端在写入前限制完整 UTF-8 请求帧（含换行）小于 128 KiB；超限返回 request_too_large，保持现有通信和会话。大量规则出站凭据可能先于数量上限达到传输限制。

Hysteria2 固定为 QUIC + TLS，公开 options 增加 obfs（空或 salamander）、upMbps / downMbps（0 自动）、serverPorts（端口或冒号范围）、hopIntervalSeconds（0 默认或 5–86400 秒）及 certificateSha256（完整证书 DER 摘要）。混淆密码位于加密凭据 obfsPassword。Clash `fingerprint` 和分享链接 `pinSHA256` 映射至证书摘要，指纹有值时始终校验，不能被 `insecure` 绕过；对应核心扩展见 [说明](../native/core/README.md)。不支持的证书、客户端证书和 QUIC 扩展在导入时拒绝，不能静默丢弃。

Windows Hysteria2 / TUIC 的公网上游在连接时通过 IP Helper API 读取当前路由与网卡，以路由和接口的总 metric 选择活动的非隧道默认接口，仅为 proxy 出站绑定该接口；局域网和回环服务器保留原路由。节点域名的系统解析限 3 秒；若出现 `198.18.0.0/15` 标准 Fake-IP 答案，单独使用同一网卡上的 AliDNS HTTPS（`223.5.5.5`，验证 `dns.alidns.com` 证书）解析该节点域名。普通域名、direct 出站与系统 DNS 设置不被替换。直接填写 Fake-IP 字面地址会收到 `invalid_server_address`，解析和网卡不可用分别返回 `upstream_dns_failed` / `upstream_network_unavailable`；错误不包含服务器地址。接口在重新连接时重选，尚未实现跨网卡迁移。其他协议继续使用原网络行为。

telemetry 的 upload / download 为采样间隔计算的字节每秒，uploadTotal / downloadTotal 为核心实际累计字节。ip、country、countryCode 来自通过本地代理的真实出口查询；latency 为完整 HTTPS 204 请求耗时毫秒，latencyAt 为观测时间。不可用字段留空 / null；probeError 提供失败原因。图表只追加新的实际延迟样本，最多 30 个。

出口查询为 `api.ip.sb/geoip`，失败后尝试 Cloudflare `cdn-cgi/trace` 和 `ipwho.is`；延迟请求为 `www.gstatic.com/generate_204`。单次请求限 5 秒，整轮探测限 20 秒。整轮期限耗尽时也提交失败结果；断开、旧会话或被新探测取消的结果不再提交。DNS 默认使用系统解析器，Hysteria2 / TUIC 的上游例外见上文。应用在前台且连接时每 2 秒采样、30 秒发起探测，切换页面继续采样，进入后台停止 UI 轮询，核心连接继续运行。流量在同一 SQLite 事务更新日汇总、15 分钟时段、归属及每会话检查点；累计计数迟到或重复不重复入账。后台、休眠、跨日的未采样间隔在下次观测时记入当前时段，不推测真实分布。

### 流量归属接口 1

`traffic` 只接受活动的 `sessionId`。Windows/macOS/Android 使用 `1.12.25-rainlink.3`，Linux 使用 `1.12.25-rainlink.4`；核心扩展在现有鉴权组内提供 `/rainlink/traffic`。公共响应如下，数值均为累计字节，`sampledAt` 为宿主 Unix 毫秒：

```json
{"version":1,"sessionId":"session-1","epoch":"core-epoch-1","sampledAt":1792483200000,"uploadTotal":100,"downloadTotal":300,"limited":false,"targets":[{"id":"node-1","kind":"node","name":"东京节点","upload":100,"download":300}],"applications":[{"id":"app-example","kind":"application","name":"chrome.exe","upload":100,"download":300}]}
```

`targets` 与 `applications` 是同一总流量的两种独立划分，每个分区的上下行分别等于总计，不能把两个排行相加。核心在 TCP/UDP 字节回调累计，并为每条流固定实际出站和应用计数器；已结束连接继续保留，在线切模式不会改变旧连接归属。宿主在连接时冻结标签与节点/代理链身份，分组规则归属实际节点。应用优先使用 Android package，否则只保留进程 basename，公共应用 ID 为该名称的 SHA-256；不会返回 PID、用户名或完整进程路径。进程查找不可用时继续统计为未知。

未知出站为 `kind=unknown,id=unassigned,name=未归属流量`，未知应用为 `kind=application,id=unassigned,name=未识别应用`。核心每周期最多 2,048 个出站/应用组合及一个溢出计数器、127 个已识别应用，超限不丢字节而归入未知并返回 `limited=true`。公共响应最多 35 个出站、128 个应用。接口故障、版本不符、分区不守恒或身份无效均报错，本次不入账，不能降级为当前选中节点的推测。隔离测速宿主 `serve-test` 不开放此命令。

SQLite schema 8 将日汇总、15 分钟时段、出站/应用归属、核心 epoch 和每个来源的累计检查点在同一事务保存。累计字节判定样本顺序；重复或较旧样本不重复入账，系统时钟回拨不冻结后续统计。单个来源计数回退/缺失、同一 session 更换 epoch、分区不守恒或数值溢出整笔回滚。旧版聚合检查点升级后的首个精确样本缺少来源基线，该间隔只记为未知，后续才按来源增量记录，不重写历史。

每日归属按实际持久采样时刻的本地日历日记账；跨日、休眠或后台间隔不按秒推测分布。正常断开尝试最后采样；核心/宿主突然退出前尚未采集的字节无法补回。旧版日汇总保留总量，在两个排行中各自补足未知，不生成虚假时段。详细时段保留 400 天，日汇总和检查点继续保留；页面只查询所选周期。CSV 的“周期归属”与“周期应用归属”也是独立分区，见[真实流量归属验收](verification/traffic-accounting.md)。

## 退出与恢复

### Windows TUN

`connect.tun` 默认为 false。为 true 时，宿主通过系统 `runas` 启动固定的 `tun-core` 权限进程；GUI 与普通宿主保持原权限。权限进程只允许运行 SHA-256 与构建锁匹配的旁置核心，配置不写入磁盘或 argv。随机 Named Pipe 使用当前用户/管理员/SYSTEM ACL、拒绝远程连接、双向 PID 及可执行文件路径校验；该管道仅用于权限进程，不替换 GUI/stdin 通道。

同一核心包含回环 mixed 与 TUN 入站，使用唯一 `RainLink-*` 网卡、双栈地址、自动/严格路由、上游接口保护及优先 DNS 拦截。响应包含 `tun` 布尔值和开启时的 `tunInterface`，只有控制 API、实际网卡和 IPv4/IPv6 广域路由确认成功才返回 connected。系统代理与 TUN 独立，均在原活动目标的同一个核心中工作。`snapshot` 会重新检查 TUN 网卡和路由，丢失时保留活动快照并返回失败，供断开恢复。

切换 TUN 使用 disconnect/connect，保留原目标、规则、模式和已应用网络配置；失败时尝试恢复原会话配置，不能采用尚未应用的新选择。`cancel` 同时取消排队和尚在授权的连接；迟到权限进程拿不到配置，不能启用网卡。权限进程在启动子核心前加入带退出回收的 Job，子进程继承保护；父宿主退出/管道 EOF 会结束核心，全局内核租约防止多个 RainLink TUN 并行。停止后确认虚拟网卡消失，清理未完成保留错误供重试。详见 [TUN 验收与未测边界](verification/tun.md)。

核心 Clash API 仅绑定 127.0.0.1 的随机端口，使用每次会话随机 secret。混合入站也只监听回环地址。配置通过核心 stdin 传入。Windows Job Object 在宿主退出时结束核心；独立 watch-proxy 进程等待宿主结束，再恢复持久代理记录。该记录由 DPAPI 加密，保存在用户缓存的 `RainLink/runtime`。

代理修改包括 ProxyEnable、ProxyServer、ProxyOverride、AutoConfigURL、AutoDetect，使用用户级互斥锁、恢复日志及回读。正常断开、窗口关闭、管道 EOF、核心退出均执行恢复。已提交设置若被其他客户端改写，则保留后来的设置；恢复失败保留记录和错误供重试，不能报告虚假成功。

Flutter 超时会关闭管道，宿主在 EOF 时取消连接并清理；强制退出宿主由 watcher 接管。窗口正常关闭等待断开与宿主退出，恢复失败保留窗口。

开发时可通过 `--dart-define=RAINLINK_HOST_PATH=...` 指定宿主，发布构建只查找应用旁的宿主。Linux 普通核心以 `Pdeathsig` 绑定创建线程，该线程保留到回收；管道 EOF 正常清理，强杀宿主也会结束核心。GNOME / KDE 系统代理共用 `$XDG_STATE_HOME/RainLink/system-proxy` 恢复租约（未设置时为 `~/.local/state`），由 Secret Service 主密钥加密，目录 0700、文件 0600。保留原 GNOME 日志文件名和加密 scope；version 2 记录后端与配置目录绑定，并读取旧 version 1 日志。独立 watcher 用 pidfd 监控宿主，确认就绪后才允许接管；正常退出、EOF、核心异常及宿主强退均恢复原配置。新代理所有者的路由和单独编辑的绕过列表得到保留；恢复失败保留日志供重试。隔离测速宿主不读取或恢复主会话租约。

GNOME 接管通过一次 dconf changeset 提交，恢复保留未设置项目，逐项 reset 前持久保存目标。宿主核对 dconf 服务身份和配置目录，拒绝 memory backend、客户端/服务配置目录不一致等无法可靠回读的环境。KDE 通过 KConfig 保留默认和未设置项，提交后独立回读并发出配置变更通知；不支持的字段修饰和锁定项拒绝接管。跨桌面恢复按日志中的后端执行，配置目录变化会保留日志并报错。

Linux TUN 条件能力代码已接入首页，完整产品连接仍待验收，见[当前检查点](verification/linux-tun-product.md)。`internal/linuxnet` 提供有界双栈观察、上游选择及歧义拒绝的规则删除；`internal/linuxtun` 提供 root 租约、持久记录与精确恢复。Linux 核心自 `.2` 的显式 `rainlink_managed=true` 使用独占网卡及协议 242，避免上游区间删除；16 条规则由 guardian 恢复，version 2 记录兼容 version 1，见[托管核心验收](verification/linux-managed-tun-core.md)。内部 `watch-tun` 仅供 root 通过继承管道启动，pidfd 就绪后监控原进程死亡，恢复先停止绑定核心。普通 Manager 已接入真实密钥环、连接、遥测、模式、日志与确认恢复；此前原生验收见[权限日志](verification/linux-tun-logs.md)，后续活动桌面授权安装见[图形授权](verification/linux-graphical-service-management.md)。macOS 原生运行及 iOS 扩展仍未完成，Android 使用独立原生通道，见[Android 验收](verification/android.md)。


## Linux 权限服务安装管理（开发阶段）

安装器在各持久写入边界检查取消；提交前取消恢复原版本，持久提交后取消保留已确认的版本并完成清理。50 个边界单元场景及五种真实 systemd 私有 checkpoint 场景通过，普通 broker 写入中取消仍待端到端验证，见[取消与恢复](verification/linux-install-cancellation.md)。

2026-10-20 续验已通过普通用户真实 pkexec 的安装、恢复、卸载、不同构建替换、授权后锁等待时取消及 EOF。共享桌面安全退出等待原管理操作及状态回读，退出失败恢复入口。活动桌面认证弹窗、事务写入期间取消与 Linux GUI 实机仍待验收，详见[续验记录](verification/linux-tun-service-management-acceptance.md)；下文原协议描述中的未验收说明属于首次实现检查点。

Linux 设置页使用独立的 `rainlink-host manage-tun-service` 进程，通过 stdin/stdout 交换逐行 JSON；不复用活动网络会话。请求为 `{id,method,payload?}`，`payload` 只能省略或为空对象；ID 必须为递增的正整数，单行最多 4096 字节，拒绝重复字段、大小写别名、额外参数和任意路径。

| 方法 | 结果 / 行为 |
| --- | --- |
| status | 只读返回 `protocolVersion:1`、`state`、`canManage`、`enabled`、`active`、中文 `message`；不请求授权或启动网络接管 |
| install | 经系统授权调用固定安装/更新动作；实际完成才返回 `{completed:true}` |
| uninstall | 经系统授权调用固定卸载动作；实际完成才确认 |
| recover | 经系统授权调用固定事务恢复动作；实际完成才确认 |
| cancel | 返回 `{requested:true}` 仅表示已请求取消，原操作结束前保持忙碌 |

`state` 为 `missing/current/different/incomplete/unavailable`。`incomplete` 或 `unavailable` 时 UI 不显示未确认的启动/开机状态。状态只证明可观察文件及 socket 状态，不证明私有安装事务已经完成。管理动作前必须断开网络会话，操作期间禁止新连接；完成或失败后重新读取状态，不能仅凭完成回执宣称安装成功。

宿主通过固定且已检查的 `/usr/bin/pkexec` 启动当前运行 inode 的 `manage-tun-elevated` 固定动作；认证由系统桌面 agent 负责，应用不处理密码。取消先关闭控制管道，并向待认证进程发送 SIGTERM；切换 root 后的 EPERM 属于预期，worker 继续依靠 EOF 取消并完成有界恢复。不会以 SIGKILL 中断 root 安装。读取限 15 秒，操作限 8 分钟，Flutter 请求限 9 分钟。普通用户真实管理闭环及 AUTH_ADMIN 的取消、EOF、认证代理拒绝已经通过 VM；D-Bus 测试代理不代表图形桌面或密码验收，见[认证取消记录](verification/linux-service-authentication-cancellation.md)。公开 Linux TUN 仍为 false。

## Linux root 权限服务（内部阶段）

普通 Flutter/host 的公开协议与 Linux `tun=false` 能力保持原样。普通 Manager 已接入私有客户端的凭据、生命周期、遥测、模式、脱敏日志与恢复，15 个完整宿主场景通过；固定路径 root 安装、升级、卸载及事务恢复已有真实 systemd 续验。VM 中 polkit 使用临时 YES / NO 规则，活动桌面认证提示尚待验收。`rainlink-host serve-tun` 只供 root 的单连接 Unix socket 服务调用；`recover-tun` 为 root 的显式补充恢复入口。

内部协议版本 1，四字节大端帧长、最多 128 KiB、严格 JSON，拒绝重复字段与大小写别名 envelope。命令为 `{version:1,id,method,payload?}`：生产客户端先发送无 payload 的 `hello-logs`（id 1），获取 guardian 身份并显式启用日志，再发送 `start`（id 2），payload 为节点/代理链、分流、runtimeSettings 及内存凭据域模型。成功后发送无 payload 的 `stop`（id 3）；取消通过关闭 socket。旧 `hello` 和直接 `start` 入口保留，不会收到异步日志；旧服务无法协商日志时报 `tun_service_handshake_failed`。核心 JSON、程序路径、授权 subject 和资源租约不由请求决定。

日志事件为 `{version:1,event:"logs",batch:LogBatch,ticks:[...]}`，可在启动回执前、运行中及停止回执前出现。客户端严格校验完整批次并再次脱敏，再由普通宿主分配公共 ID / 游标。每连接缓冲 2,000 条，每批最多 16 条、100 ms 至多一批，日志帧写入最多 1 秒，核心输出不等待 IPC；半帧失败需确认恢复。停止先恢复，再发送最新两批日志，最后回执；跳过积压明确标注 dropped。Linux 清空使用直接内核单调时间屏障，排队旧记录不会复活；时钟失败为 `logs_unavailable`，原记录保留。

身份使用 SO_PEERCRED 和 SO_PEERPIDFD，要求 Linux 6.5+；调用方与服务的网络 namespace 必须一致，授权后再次核对 PID、启动时刻、boot ID 与四个 UID。固定 polkit action `org.rainlink.tun.manage`，执行经过 root 目录与 inode 校验的 pkcheck，最多 60 秒。授权器与核心均不继承调用方环境。

回执为 `{version:1,id,result? ,error?}`。hello 的 result 为 guardian 的 `{pid,start,boot}`；socket activation 的 SO_PEERCRED 可能对应监听者，不能替代该 guardian 身份。成功 start 的私有 result 为 `{snapshot,apiPort,apiSecret,resources}`，原生宿主只能把 snapshot 交给 Flutter；resources 为 root 自行分配的接口/表/优先级，供普通宿主实时观察。失败只有安全错误码，不携带核心原文。snapshot 必须在真实 API、TUN、双栈路由和全部 16 条托管规则确认后变为 connected。stop 只有在核心退出、精确恢复及 journal 删除后才确认 stopped；失败为 recovery_pending，不伪造停止成功。

独立连接可发送无 payload 的 `idle`，只返回 `{idle:bool}` 或恢复待定错误；它只在独占锁内观察 journal，不执行恢复或结束其他进程，也不触发 polkit。服务丢失或启动未确认时，普通宿主保留失败会话或 pending 状态；必须先确认原 guardian 退出，再取得 idle=true，才允许完成断开。接口消失、EOF 或暂时不存在 journal 均不足以确认恢复。

原生客户端逐级验证固定 `/run/rainlink/tun.sock` 的 root 目录与 inode，使用 procfs FD 连接经过检查的 socket，不重新解析可替换路径。启动最长八十秒，取消通过关闭通道；成功后与启动操作 context 分离，避免普通请求结束时断开会话。停止至多二十八秒、帧写入至多两秒，多个并发停止只发送一次；EOF、超时、异常回执与恢复待定均不能当作确认停止。

普通宿主 disconnect 的操作时限为 45 秒，Flutter 单独等待 50 秒；普通读取仍为 25 秒。前阶段[宿主接入](verification/linux-tun-manager.md)、[权限通信](verification/linux-tun-permission.md)、[私有转发](verification/linux-tun-forwarding.md)及[安装验收](verification/linux-tun-install.md)保留原始范围。最新 15 场景、实际核心日志和真实 systemd / polkit 的 VM 允许 / 拒绝见[日志验收](verification/linux-tun-logs.md)，活动桌面认证提示未验收。

## 可视化代理链

`chain` 包含 id、name、revision、hops（2–5 个有序 node 快照）。与 node 恰选其一。响应 target 为公开的 id/name/revision/kind（node 或 chain）；单节点继续附带旧 node 字段，链不伪装为节点。主链的逐跳绑定键为 `proxy/hop/0` 等，规则链为 `chain:ID` 及 `chain:ID/hop/0` 等；连接时核对全部修订和顺序。规则目标支持 `chain:ID`，全部引用在连接事务冻结。

链路校验和测试使用独立的 `rainlink-host serve-test`，只允许 hello、validateChain、testChain、testNode、validateSettings、testDNS、cancel，不能连接正常会话或修改系统代理。它使用独立临时目录，EOF 取消并清理临时核心。正常 serve 拒绝这些隔离校验和测试命令。validateChain 只执行 core check；testChain 实际逐前缀访问固定 HTTPS 204 站点，每前缀最多 8 秒，总限 45 秒，Flutter 测试请求限 50 秒。结果为 fingerprint（有序节点 ID 和修订的 SHA256）、checkedAt、passed、hops；各项包含 hop、latency、passed、error。失败定位路径前缀，不暴露原始核心错误、凭据或 URL。

## 节点独立测速

`serve-test` 的 `testNode` payload 直接为一个 `node`，返回 nodeId、revision、checkedAt（Unix 毫秒）、passed、latency（毫秒）、error；失败可附 failureCode 和 httpStatus。分类为 timeout、tls_failed、http_status、core_start_failed、request_failed、invalid_response，错误只包含安全中文描述。Flutter 校对节点 ID 与修订，旧版本回执不会显示到编辑后的节点。

测试使用临时核心经该节点访问 `www.gstatic.com/generate_204`，只接受 HTTP 204，不跟随跳转，响应最多 4096 字节；请求最多 5 秒，单节点整体最多 8 秒。每个测试有独立宿主和临时目录，Flutter 请求上限 20 秒，批量并发最多 3 个、每批最多 2000 个。关闭测试管道会取消请求并回收核心，节点测试与代理链测试分别取消，不触碰正常会话。取消清理失败会保留重试入口，不能报告成功。

节点本地别名、收藏、隐藏保存在 SQLite schema 5 的 NodeOverrides 表，外键级联清理；不作为核心路由参数，不改变连接修订。隐藏清除该节点的后续选择与分组记忆，并从新目标列表排除；已有规则和代理链明确引用仍保留，当前活动快照不变。刷新按节点稳定身份保留覆盖，身份被替换时清理，避免旧设置误用到新节点。

## 网络与核心设置

2026-10-17 增加可选 `runtimeSettings.advanced`，值为不超过 16 KiB 的 JSON **字符串**，默认空字符串或 `{}`。Flutter 先把 YAML/JSON 转为结构模型，宿主再严格检查字段、类型、重复键与引用，并与受控配置合并后执行真实核心 check。只允许 log、dns、route 的明确子集；完整字段、合并优先级及恢复流程见 [高级配置验收](verification/advanced-config.md)。该字段随活动快照回传并逐字核对。节点认证、监听、控制 API 和 TUN 不允许覆盖。

高级配置确认应用时保留原活动目标/链/规则/模式及接管选项；启动或落盘失败尝试恢复原连接。两版片段在同一 SQLite 事务存储，基础网络表单不能替换高级片段。DNS 基础测试仍测试网络页的解析器，界面明确显示其范围；高级配置中的 DNS 则在实际会话内运行。校验取消与基础 DNS 测试分别回收各自的隔离宿主。

`connect.runtimeSettings` 为 `{proxyPort, dnsMode, resolver, bootstrapDns, ipv6, logLevel}`。默认值依次为 `0`、`system`、`https://dns.alidns.com/dns-query`、`223.5.5.5`、`false`、`info`。端口 0 自动选择，固定端口范围 1–65535，仅监听回环；被占用时连接失败，不偷偷换端口。dnsMode 为 system / encrypted / custom，encrypted 只允许 HTTPS，custom 允许 HTTPS 或 `udp://IP:端口`，不接受认证、query、fragment、无效端口。bootstrapDns 必须为 IP，用于解析 HTTPS 解析器域名，不是自动回退服务器。ipv6 控制 DNS strategy（ipv4_only / prefer_ipv4），不阻止字面 IPv6 节点。logLevel 为 debug / info / warn / error。

网络设置冻结到每次连接；连接快照回传实际 `runtimeSettings`，Flutter 逐项核对，不接受旧宿主忽略参数后报告成功。旧调用不传该字段时使用默认值。保存设置不会调用活动核心，下一次连接才应用。界面确认重启时先断开，使用原活动节点/链及规则密文快照、当前模式和最新网络设置重新连接；取消或迟到结果不能重建会话。

独立 `serve-test` 新增 `validateSettings` 和 `testDNS`，payload 均直接为 runtimeSettings，不携带节点凭据。前者编译受控配置并执行实际 `sing-box check`，失败不落盘；后者查询 example.com 的 A 记录，返回实际 `addresses`、`latency`（毫秒）。system 使用本机解析器，UDP 使用所填 IP/端口，HTTPS 使用 POST application/dns-message、正常 TLS 校验、不跟随重定向，最多 64 KiB；解析最多 6 秒，Flutter 请求最多 12 秒。取消关闭该诊断宿主，EOF 取消操作，与正常连接、系统 DNS 和系统代理隔离。

Linux root 管理命令：`install-tun`、`uninstall-tun`、`recover-tun-install`，不接受目标路径或执行命令参数。原 `recover-tun` 保留严格恢复语义；仅 systemd 每连接退出钩子使用 `recover-tun-service`，另一个租约仍活动时明确跳过，不作为断开成功回执。
