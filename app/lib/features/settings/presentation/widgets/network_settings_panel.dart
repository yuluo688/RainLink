import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/preferences/device_settings_controller.dart';
import '../../../../design_system/theme/rainlink_colors.dart';
import '../../../../design_system/widgets/rainlink_icon.dart';
import '../../../../design_system/widgets/surface_card.dart';
import '../../../../domain/core/runtime_settings.dart';
import 'settings_rows.dart';

class NetworkSettingsPanel extends ConsumerStatefulWidget {
  const NetworkSettingsPanel({super.key});
  @override
  ConsumerState<NetworkSettingsPanel> createState() =>
      _NetworkSettingsPanelState();
}

class _NetworkSettingsPanelState extends ConsumerState<NetworkSettingsPanel> {
  late CoreRuntimeSettings _draft;
  late final TextEditingController _port;
  late final TextEditingController _resolver;
  late final TextEditingController _bootstrap;
  final _form = GlobalKey<FormState>();
  RuntimeSettingsGateway? _gateway;
  String _message = '';
  bool _error = false;
  bool _saving = false;
  bool _testing = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(deviceSettingsControllerProvider).runtime;
    _gateway = ref.read(runtimeSettingsGatewayProvider);
    _port = TextEditingController(text: '${_draft.proxyPort}');
    _resolver = TextEditingController(text: _draft.resolver);
    _bootstrap = TextEditingController(text: _draft.bootstrapDns);
  }

  @override
  void dispose() {
    ++_generation;
    if (_testing) {
      unawaited(_gateway
          ?.cancelDnsTest()
          .catchError((Object error, StackTrace stack) {
        FlutterError.reportError(FlutterErrorDetails(
            exception: error, stack: stack, library: 'RainLink DNS cleanup'));
      }));
    }
    _port.dispose();
    _resolver.dispose();
    _bootstrap.dispose();
    super.dispose();
  }

  void _edit(VoidCallback change) => setState(() {
        change();
        _message = '';
        _error = false;
      });

  Future<void> _submit({bool test = false}) async {
    if (_saving || _testing || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _saving = !test;
      _testing = test;
      _message = '';
      _error = false;
    });
    try {
      final settings = _draft
          .copyWith(
              proxyPort: int.parse(_port.text.trim()),
              resolver: _resolver.text.trim(),
              bootstrapDns: _bootstrap.text.trim())
          .validated();
      String message;
      if (test) {
        final gateway = _gateway;
        if (gateway == null) throw const SettingsException('当前平台尚未接入解析测试');
        final result = await gateway.testDns(settings);
        message =
            'example.com → ${result.addresses.join('、')} · ${result.latency} ms';
      } else {
        final latest = ref.read(deviceSettingsControllerProvider).runtime;
        await ref
            .read(deviceSettingsControllerProvider.notifier)
            .saveRuntime(settings.copyWith(logLevel: latest.logLevel));
        message = '网络设置已保存，下一次连接时应用。';
      }
      if (mounted && generation == _generation) {
        setState(() => _message = message);
      }
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _message = '$error';
          _error = true;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _saving = false;
          _testing = false;
        });
      }
    }
  }

  Future<void> _cancelTest() async {
    ++_generation;
    try {
      await _gateway?.cancelDnsTest();
      if (mounted) {
        setState(() {
          _message = '解析测试已取消';
          _error = false;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _message = '测试进程尚未退出，请稍后重试。';
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _testing;
    final available = ref.watch(runtimeSettingsGatewayProvider) != null;
    final colors = RainlinkColors.of(context);
    final advanced = ref.watch(deviceSettingsControllerProvider
        .select((value) => value.runtime.advanced));
    return Form(
        key: _form,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SettingsPanelHeading('网络', '管理解析方式与本地监听，保存后在下次连接时应用。'),
          if (advanced.overrides('dns')) ...[
            SurfaceCard(
                padding: const EdgeInsets.all(12),
                child: Text(
                    '当前 DNS 含高级配置覆盖。以下编辑和测试针对基础 DNS；已覆盖字段以“核心引擎 → 高级配置”为准。引导 DNS 仍用于解析服务器域名。',
                    key: const ValueKey('dns-advanced-source'),
                    style: Theme.of(context).textTheme.bodySmall)),
            const SizedBox(height: 12),
          ],
          SurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final mode in DnsMode.values)
                        ChoiceChip(
                            key: ValueKey('dns-${mode.name}'),
                            label: Text(switch (mode) {
                              DnsMode.system => '系统 DNS',
                              DnsMode.encrypted => '加密 DNS',
                              DnsMode.custom => '自定义 DNS'
                            }),
                            showCheckmark: false,
                            selected: _draft.dnsMode == mode,
                            onSelected: busy
                                ? null
                                : (_) => _edit(() {
                                      _draft = _draft.copyWith(dnsMode: mode);
                                      if (mode == DnsMode.encrypted &&
                                          !(_resolver.text
                                              .startsWith('https://'))) {
                                        _resolver.text =
                                            const CoreRuntimeSettings()
                                                .resolver;
                                      }
                                    })),
                    ]),
                    const SizedBox(height: 16),
                    if (_draft.dnsMode == DnsMode.system)
                      Text('使用操作系统的解析器，不修改系统 DNS。',
                          style: Theme.of(context).textTheme.bodySmall)
                    else ...[
                      TextFormField(
                          key: const ValueKey('dns-resolver'),
                          controller: _resolver,
                          enabled: !busy,
                          decoration: InputDecoration(
                              labelText: '首选解析器',
                              hintText: _draft.dnsMode == DnsMode.encrypted
                                  ? 'https://dns.alidns.com/dns-query'
                                  : 'https://… 或 udp://1.1.1.1:53'),
                          onChanged: (_) => _edit(() {}),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? '请输入解析器地址'
                              : null),
                      const SizedBox(height: 16),
                      TextFormField(
                          key: const ValueKey('dns-bootstrap'),
                          controller: _bootstrap,
                          enabled: !busy,
                          decoration: const InputDecoration(
                              labelText: '引导解析器',
                              helperText: '用于解析 HTTPS 解析器的域名，填写 IP 地址。'),
                          onChanged: (_) => _edit(() {})),
                      const SizedBox(height: 12),
                      Text('解析请求通过本机网络发送；HTTPS 会加密解析内容。',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                          key: const ValueKey('test-dns'),
                          onPressed: !available || _saving
                              ? null
                              : _testing
                                  ? _cancelTest
                                  : () => _submit(test: true),
                          icon: RainlinkIcon(
                              _testing
                                  ? RainlinkGlyph.close
                                  : RainlinkGlyph.speed,
                              size: 16),
                          label: Text(_testing ? '取消测试' : '测试解析')),
                      FilledButton(
                          key: const ValueKey('save-network'),
                          onPressed:
                              available && !busy ? () => _submit() : null,
                          child: Text(_saving ? '正在校验…' : '保存设置')),
                    ]),
                    if (!available) ...[
                      const SizedBox(height: 12),
                      Text('当前平台暂不支持应用网络设置。',
                          style: Theme.of(context).textTheme.bodySmall)
                    ],
                    if (_message.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Semantics(
                          liveRegion: true,
                          child: Text(_message,
                              key: const ValueKey('network-feedback'),
                              style: TextStyle(
                                  color: _error ? colors.error : colors.primary,
                                  fontSize: 12)))
                    ],
                  ])),
          const SizedBox(height: 12),
          SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: [
                SettingsToggleRow(
                    title: 'IPv6 解析',
                    description: '允许域名返回 IPv6 地址',
                    value: _draft.ipv6,
                    onChanged: busy
                        ? null
                        : (v) =>
                            _edit(() => _draft = _draft.copyWith(ipv6: v))),
                const Divider(height: 1),
                SettingsRow(
                    title: '混合端口',
                    description: '本机 HTTP / SOCKS5 · 0 为自动分配',
                    controlWidth: 112,
                    control: TextFormField(
                        key: const ValueKey('mixed-port'),
                        controller: _port,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(isDense: true),
                        onChanged: (_) => _edit(() {}),
                        validator: (v) {
                          final port = int.tryParse(v?.trim() ?? '');
                          return port == null || port < 0 || port > 65535
                              ? '端口 0–65535'
                              : null;
                        })),
              ])),
        ]));
  }
}
