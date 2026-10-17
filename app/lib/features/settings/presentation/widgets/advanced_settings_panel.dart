import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/connection/session_controller.dart';
import '../../../../application/preferences/device_settings_controller.dart';
import '../../../../design_system/layout/app_layout.dart';
import '../../../../design_system/theme/rainlink_colors.dart';
import '../../../../design_system/widgets/rainlink_icon.dart';
import '../../../../design_system/widgets/surface_card.dart';
import '../../../../domain/core/advanced_config.dart';
import '../../../../domain/core/runtime_settings.dart';
import '../../../../platform/export/file_data_export_service.dart';

enum _ConfigAction { previous, clear, export }

class AdvancedSettingsPanel extends ConsumerStatefulWidget {
  const AdvancedSettingsPanel({required this.onBack, super.key});
  final VoidCallback onBack;

  @override
  ConsumerState<AdvancedSettingsPanel> createState() =>
      _AdvancedSettingsPanelState();
}

class _AdvancedSettingsPanelState extends ConsumerState<AdvancedSettingsPanel> {
  late final TextEditingController _editor;
  RuntimeSettingsGateway? _gateway;
  ConfigFormat _format = ConfigFormat.yaml;
  AdvancedConfig? _checked;
  CoreRuntimeSettings? _checkedRuntime;
  String _message = '';
  bool _error = false;
  bool _validating = false;
  bool _applying = false;
  bool _exporting = false;
  int _revision = 0;
  bool get _busy => _validating || _applying || _exporting;

  @override
  void initState() {
    super.initState();
    _gateway = ref.read(runtimeSettingsGatewayProvider);
    _editor = TextEditingController(
        text: ref
            .read(deviceSettingsControllerProvider)
            .runtime
            .advanced
            .render(_format));
    _lastText = _editor.text;
    _editor.addListener(_edited);
  }

  void _edited() {
    // Selection/caret movement must not invalidate a successful check.
    if (_lastText == _editor.text) return;
    _lastText = _editor.text;
    final checking = _validating;
    final revision = ++_revision;
    setState(() {
      _validating = false;
      _checked = null;
      _checkedRuntime = null;
      _message = '';
      _error = false;
    });
    if (checking) {
      unawaited(_cancelEditedValidation(revision));
    }
  }

  Future<void> _cancelEditedValidation(int revision) async {
    try {
      await _gateway?.cancelValidation();
    } on Exception {
      if (mounted && revision == _revision) {
        _notice('上次校验尚未退出，请稍后重新校验。', error: true);
      }
    }
  }

  String? _lastText;

  @override
  void dispose() {
    ++_revision;
    if (_validating) {
      unawaited(_gateway
          ?.cancelValidation()
          .catchError((Object error, StackTrace stack) {
        FlutterError.reportError(FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'RainLink config cleanup'));
      }));
    }
    _editor.dispose();
    super.dispose();
  }

  void _notice(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _error = error;
    });
  }

  void _changeFormat(ConfigFormat format) {
    if (_busy || format == _format) return;
    try {
      final parsed = AdvancedConfig.parse(_editor.text, _format);
      _editor.text = parsed.render(format);
      setState(() => _format = format);
    } on Exception catch (error) {
      _notice('$error', error: true);
    }
  }

  Future<void> _validate() async {
    if (_busy) return;
    final revision = ++_revision;
    setState(() {
      _validating = true;
      _checked = null;
      _message = '';
    });
    try {
      final config = AdvancedConfig.parse(_editor.text, _format);
      final runtime = ref.read(deviceSettingsControllerProvider).runtime;
      final gateway = _gateway;
      if (gateway == null) throw const SettingsException('当前平台尚未接入配置校验');
      await gateway.validateRuntime(runtime.copyWith(advanced: config));
      if (!mounted || revision != _revision) return;
      setState(() {
        _checked = config;
        _checkedRuntime = runtime;
      });
      _notice('核心校验通过，可确认应用。');
    } on Exception catch (error) {
      if (mounted && revision == _revision) _notice('$error', error: true);
    } finally {
      if (mounted && revision == _revision) setState(() => _validating = false);
    }
  }

  Future<void> _apply() async {
    final config = _checked;
    final runtime = _checkedRuntime;
    if (_busy || config == null || runtime == null) return;
    final session = ref.read(sessionControllerProvider);
    final sessionRevision =
        ref.read(sessionControllerProvider.notifier).operationRevision;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('应用高级配置？'),
              content: Text(session.connected
                  ? '当前连接会短暂断开，随后仍使用“${session.active?.target.name ?? '当前目标'}”重新连接。应用失败会尝试恢复原连接。'
                  : '保存后在下一次连接时使用。上一版配置会保留，可随时恢复。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    key: const ValueKey('confirm-advanced'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('确认应用')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _applying = true);
    try {
      await ref.read(deviceSettingsControllerProvider.notifier).applyAdvanced(
          config,
          expectedRuntime: runtime,
          expectedSessionRevision: sessionRevision);
      if (!mounted) return;
      setState(() {
        _checked = null;
        _checkedRuntime = null;
      });
      _notice(session.connected ? '高级配置已应用，连接已恢复。' : '高级配置已保存，下次连接时应用。');
    } on Exception catch (error) {
      _notice('$error', error: true);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _action(_ConfigAction action) async {
    if (_busy) return;
    switch (action) {
      case _ConfigAction.previous:
        final previous =
            ref.read(deviceSettingsControllerProvider).previousAdvanced;
        if (previous != null) {
          _editor.text = previous.render(_format);
          _notice('已载入上一版，请校验后确认应用。');
        }
      case _ConfigAction.clear:
        _editor.text = const AdvancedConfig.empty().render(_format);
        _notice('已清除草稿中的覆盖，请校验后确认应用。');
      case _ConfigAction.export:
        final config = _checked;
        if (config == null) return;
        setState(() => _exporting = true);
        try {
          final path = await ref.read(dataExportServiceProvider).save(
              suggestedName: 'rainlink-advanced.${_format.name}',
              content: '${config.render(_format)}\n');
          if (path != null) _notice('配置已导出到所选位置');
        } on Exception {
          _notice('配置导出失败，请检查保存位置与磁盘空间。', error: true);
        } finally {
          if (mounted) setState(() => _exporting = false);
        }
    }
  }

  void _help() => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
            title: const Text('高级配置支持范围'),
            content: const SizedBox(
                width: 480,
                child: SingleChildScrollView(
                    child: SelectableText(
                        '采用 sing-box 字段，按需覆盖，使用 {} 清除覆盖。节点密码、监听端口、控制接口和 TUN 由 RainLink 管理，不在这里编辑。\n\n'
                        'log：level（debug/info/warn/error）、timestamp。\n\n'
                        'dns：servers（local/udp/tcp/tls/https）、final、strategy、disable_cache、disable_expire、independent_cache、cache_capacity、rules。服务器支持 tag、server、server_port、HTTPS path 和 TLS server_name。域名解析使用网络页的引导 DNS。\n\n'
                        'DNS 标签省略时为 server-1、server-2。system 表示系统 DNS，default 表示网络页的 DNS；添加服务器后默认使用第一个，可通过 final 指定。\n\n'
                        '规则匹配支持 domain、domain_suffix、domain_keyword 列表。DNS 规则支持 server 或 action: reject；route.rules 还支持 ip_cidr、ip_is_private: true、port、network 列表，以及 outbound: proxy/direct 或 action: reject。\n\n'
                        '补充分流规则先于规则页执行，概览中的全局/直连模式和 TUN DNS 接管仍优先。每个字段最多 64 项，最多 8 个 DNS 服务器、各 64 条规则、总计 16 KB。\n\n'
                        '示例：\n'
                        'dns:\n  servers:\n    - tag: secure\n      type: https\n      server: dns.alidns.com\n  final: secure\n  independent_cache: true\n'
                        'route:\n  rules:\n    - domain_suffix: [example.com]\n      outbound: direct'))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'))
            ],
          ));

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(deviceSettingsControllerProvider);
    final colors = RainlinkColors.of(context);
    final desktop = AppLayout.current == AppLayout.desktop;
    final compactEditor = desktop && MediaQuery.sizeOf(context).height < 700;
    final currentCheck = _checkedRuntime != null &&
        jsonEncode(device.runtime.toJson()) ==
            jsonEncode(_checkedRuntime?.toJson());
    final available = ref.watch(runtimeSettingsGatewayProvider) != null;
    final session = ref.watch(sessionControllerProvider);
    final sources = [
      if (device.runtime.advanced.overrides('dns')) 'DNS',
      if (device.runtime.advanced.overrides('route')) '分流规则',
      if (device.runtime.advanced.overrides('log')) '日志',
    ].join('、');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (desktop) ...[
        Row(children: [
          IconButton(
              key: const ValueKey('advanced-back'),
              tooltip: '返回核心引擎',
              onPressed: _applying ? null : widget.onBack,
              icon: const RainlinkIcon(RainlinkGlyph.back)),
          const SizedBox(width: 4),
          Expanded(
              child:
                  Text('高级配置', style: Theme.of(context).textTheme.titleLarge)),
        ]),
        const SizedBox(height: 8),
      ],
      Text('校验后应用，出错时保留原设置。', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      SurfaceCard(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final format in ConfigFormat.values)
                  if (format == _format)
                    FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(68, 40),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12)),
                        onPressed: _busy ? null : () => _changeFormat(format),
                        child: Text(format.name.toUpperCase()))
                  else
                    OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(68, 40),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12)),
                        key: ValueKey('config-format-${format.name}'),
                        onPressed: _busy ? null : () => _changeFormat(format),
                        child: Text(format.name.toUpperCase())),
              ])),
              PopupMenuButton<_ConfigAction>(
                  key: const ValueKey('config-menu'),
                  tooltip: '配置操作',
                  enabled: !_busy,
                  icon: const RainlinkIcon(RainlinkGlyph.more),
                  onSelected: _action,
                  itemBuilder: (context) => [
                        PopupMenuItem(
                            value: _ConfigAction.previous,
                            enabled: device.previousAdvanced != null,
                            child: const Text('恢复上一版')),
                        const PopupMenuItem(
                            value: _ConfigAction.clear, child: Text('清除覆盖')),
                        PopupMenuItem(
                            value: _ConfigAction.export,
                            enabled: _checked != null && currentCheck,
                            child: const Text('导出配置')),
                      ]),
            ]),
            const SizedBox(height: 12),
            TextField(
                key: const ValueKey('advanced-editor'),
                controller: _editor,
                // Keep validation editable; every revision cancels its check.
                readOnly: _applying,
                minLines: desktop ? 8 : 10,
                maxLines: desktop ? (compactEditor ? 8 : 10) : 14,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.multiline,
                style: TextStyle(
                    fontFamily: 'Roboto Mono',
                    fontSize: 12,
                    height: 1.55,
                    color: colors.secondary),
                decoration: const InputDecoration(
                    filled: true,
                    alignLabelWithHint: true,
                    contentPadding: EdgeInsets.all(14),
                    hintText: '# 按需添加 log、dns 或 route 覆盖',
                    semanticCounterText: '配置最多 16 KB')),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                  key: const ValueKey('validate-advanced'),
                  onPressed: !_busy && available ? _validate : null,
                  icon: const RainlinkIcon(RainlinkGlyph.check, size: 16),
                  label: Text(_validating ? '正在校验…' : '校验配置')),
              FilledButton(
                  key: const ValueKey('apply-advanced'),
                  onPressed: !_busy &&
                          currentCheck &&
                          _checked != null &&
                          _checked != device.runtime.advanced &&
                          !session.working
                      ? _apply
                      : null,
                  child: Text(_applying ? '正在应用…' : '应用配置')),
            ]),
            if (_message.isNotEmpty || _checked != null && !currentCheck) ...[
              const SizedBox(height: 12),
              Text(
                  _checked != null && !currentCheck
                      ? '网络设置已变化，请重新校验配置。'
                      : _message,
                  key: const ValueKey('config-feedback'),
                  style: TextStyle(
                      color: _error ? colors.error : colors.secondary,
                      fontSize: 12)),
            ],
          ])),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: Text(sources.isEmpty ? '当前使用界面设置' : '高级覆盖：$sources',
                key: const ValueKey('config-source'),
                style: Theme.of(context).textTheme.bodySmall)),
        TextButton(onPressed: _help, child: const Text('支持范围')),
      ]),
      if (!available)
        Text('当前平台的配置校验尚未接入。', style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
