# KDE 系统代理辅助程序

这是普通用户进程，不申请 root，不启动 Qt GUI，只通过 Qt Core / D-Bus 和 KF6 ConfigCore 读写当前用户 `kioslaverc` 的八个代理字段。Go 宿主负责凭据加密、单用户租约、异常恢复和超时。

需要 Linux C++17 编译器、CMake 3.18+、pkg-config、Qt6 Core / D-Bus 6.6+ 以及 KF6 ConfigCore 的运行库和开发头文件。当前实际验证版本是 Qt 6.8.3、KConfig 6.13.0、libproxy 0.5.10；尚未据此承诺 KDE 5 或所有 Plasma 应用均支持。

```bash
bash tools/build_kde_proxy.sh
```

产物与 `rainlink-host` 放在同一目录，默认 `build/host/linux-<arch>/rainlink-kde-proxy`。`tools/dev.sh run` 在 KDE 环境自动构建，也可使用 `RAINLINK_BUILD_KDE_PROXY=1` 显式构建。Qt / KDE 动态库使用系统安装版本；本脚本没有生成 AppImage、deb 或完整 Flutter 分发包。

没有辅助程序、运行库、会话总线或可写权限时，宿主不声明系统代理能力。已存在的恢复记录按记录中的后端恢复，不依赖当前桌面名称。KDE 与 GNOME 共用一个用户租约，并保留旧 GNOME 恢复格式的读取能力。

输入输出均为有上限的单个 JSON 文档，配置值仅经 stdin/stdout 传递。辅助程序不接受文件路径或命令行值，只接受经验证的当前 XDG 配置根目录；操作范围固定为 `Proxy Settings`。写入使用 KConfig 的锁、合并及原子提交，检查 `sync()` 和独立对象回读，并发送 `/kioslaverc` 的 KConfig 变更通知。

保留原代理认证、PAC、未设置项、系统默认和无关设置。对受管理字段上的本地化、环境展开、删除标记等尚无精确恢复实现的配置拒绝接管；系统锁定项、符号链接、共享可写文件和超限数据也拒绝操作。失败保留恢复日志，不能将失败当作已恢复。

完整范围及复验入口见[验收记录](../../../docs/verification/linux-kde-proxy.md)。
