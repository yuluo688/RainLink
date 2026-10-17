# 订阅到期提醒续验 · 2026-10-17

入口为 Windows「设置 → 通用 → 订阅到期提醒」，默认关闭。已存在的通用设置缺少此字段时保持关闭；非法字段会报错。提醒仅依据已经导入的有效期，不访问订阅地址、不更改节点或活动连接。

## 行为与持久化

距离有效期不超过 3 天时提醒一次，到期时再提醒一次。没有有效期的订阅及手动分组不提醒；每次检查聚合临期/到期数量，只向系统传数量，通知中不包含名称、URL、节点或凭据。关闭托盘同时关闭连接通知和到期提醒。

正常运行期间监听本地分组更新，并每分钟检查；恢复应用时继续检查。不承诺在应用退出、Windows 休眠或未运行时定时唤醒。续期按新有效期判断，单纯更新节点不重复提醒，删除订阅时清理对应记录。

复用 schema 6 的 preferences 表，键为 `notifications.subscription_expiry`，记录分组 ID、UTC 有效期和 soon/expired 阶段。事务合并且禁止同一期阶段倒退；Windows 接受通知后才写记录。提交失败允许重试；已提交但写入失败时保留内存批次，先补写记录，本次运行中不会重复提交。正常退出等待在途提交、落盘和所有监听取消，退出开始后不能重新恢复监听。

提交与 SQLite 写入不属于同一个系统事务：进程恰好在两者之间崩溃时，下次运行仍可能再次提醒，不能承诺跨进程 exactly-once。存储损坏或失败会在通用设置显示固定脱敏错误并提供「重试」。提醒记录失败不阻止网络安全退出。

点击通知恢复窗口并通过应用路由进入「分组」。窗口守卫位于 MaterialApp 上方，因此路由由持有 GoRouter 的 RainlinkApp 处理，避免在守卫上下文查找路由失败。Windows 单托盘通知回调不携带业务载荷；连接通知和订阅通知重叠时使用最近提交类别，系统横幅队列的实际表现尚未逐一验证。

## 验证范围

单元/组件回归覆盖 3 天边界、到期、续期、未知信息、手动分组、时钟回退、关闭期间的监听取消，以及禁用/续期/删除/暂停发生在原生检查期间的竞态。真实 SQLite 触发器拒绝写入后验证不重复提交、可重试保存；设置开关保存失败保留确认值，关闭托盘联动停用，路由销毁后不再处理事件。

`app/integration_test/windows_subscription_expiry_test.dart` 使用临时文件 SQLite、真实 WindowsDesktopIntegration 和 Shell 接口验证：

- 默认关闭不产生提醒记录；原生接口拒绝非法数量和无托盘提交。
- 通用设置真实开启提醒，系统拒绝及实际 SQLite 写入失败均显示错误，按钮重试后保存两条记录。
- 向指定测试 PID 模拟 `NIN_BALLOONUSERCLICK` 回调，窗口恢复并进入分组。这证明原生回调与路由链路，不代表人工点击了系统横幅。
- 关闭并用新连接重开数据库、新建监视器后，同一期零次提交；新有效期符合条件后经真实 Shell 接受一次，后续检查不重发。
- 不请求订阅、不启用系统代理或 TUN，不修改用户数据库。

原生回执为 [windows-evidence.json](subscription-expiry/windows-evidence.json)。Windows 接口成功表示系统接受，不保证勿扰、通知权限或系统策略下实际显示横幅。

## UI 与设计稿

在原有 Figma 桌面设置 `2:19743` 通知卡内增加一行，保持 Auto Layout 和可复用开关，不增加页面。新行 `130:25677`，连接通知与订阅提醒分别说明；参考图为 [desktop-settings-expiry-final.png](reference/desktop-settings-expiry-final.png)。

`subscription_expiry_visual_test.dart` 覆盖 1440×900、960×640，深浅主题、紧凑/标准密度和 1.3 倍字号的正常/记录错误状态，并检查重试入口可见。393×852 与 320×640 的 iOS/Android 布局保留左上返回；原生提醒尚未接入的移动端不显示此开关。所有截图为隔离 fixture，不能作为手机通知或真机网络服务证据。

本轮未修改 Go 或核心配置，不重复声称进行了公网、协议或 TUN 验收。全产品后续范围见 [实现清单](../IMPLEMENTATION_STATUS.md)。

验证结果：Dart 格式及静态分析通过，Flutter 全量 **303 项通过**；Windows 原生集成及 **32 张 fixture 布局截图**通过。人工抽查了宽桌面、小桌面大字错误态和两种移动尺寸。日志分别为 `build/expiry-analyze.log`、`build/expiry-flutter.log`、`build/expiry-native.log`、`build/expiry-visual.log`。

## Release 交付

预览包为 `build/RainLink-windows-x64-expiry-preview.zip`，41,169,472 字节、75 个文件，SHA-256：`2a8fc3544465c12f8eb48508006fc89ea8ad8a62b2e3fe59bff85b5f07455260`。已核对 Release 引擎、AOT、宿主、固定核心、SVG、许可与核心源码，ZIP CRC 通过，不含用户数据库。版本仍为 0.1.0+1，schema 6。元数据见 [subscription-expiry-build.json](subscription-expiry-build.json)，最新入口为 [desktop-build.json](desktop-build.json)，旧 density/advanced/TUN 包保留。

Release 实窗检查了未连接概览、通用设置及新增提醒行，保持关闭提醒后正常退出，截图为 `subscription-expiry/release-*.png`。启动前后的节点 68、分组 1、覆盖 0、偏好 4，及 SQLite/开机启动/系统代理摘要一致；测试阶段前后也一致。原有 FlClashHelperService PID 6156 保留，RainLink、宿主和核心无残留。摘要和回执见 [release-evidence.json](subscription-expiry/release-evidence.json)。
