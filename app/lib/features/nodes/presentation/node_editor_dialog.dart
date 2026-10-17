import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/nodes/node_providers.dart';
import '../../../application/groups/group_providers.dart';
import '../../../domain/groups/node_group.dart';
import '../../../domain/groups/subscription_issue.dart';
import '../../../domain/groups/subscription_review.dart';
import '../../../domain/nodes/node_validation.dart';
import '../../../domain/nodes/proxy_node.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../design_system/theme/rainlink_colors.dart';
import '../../../design_system/widgets/rainlink_segmented_control.dart';
import '../../../design_system/widgets/rainlink_switch.dart';
import '../../../design_system/layout/app_layout.dart';
import '../../groups/presentation/subscription_review_panel.dart';

Future<void> showNodeEditor(BuildContext context,
        {ProxyNode? node, bool subscription = false}) =>
    showDialog<void>(
        context: context,
        useSafeArea: AppLayout.current == AppLayout.desktop,
        barrierDismissible: false,
        builder: (_) =>
            NodeEditorDialog(node: node, subscription: subscription));

class NodeEditorDialog extends ConsumerStatefulWidget {
  const NodeEditorDialog({this.node, this.subscription = false, super.key});
  final ProxyNode? node;
  final bool subscription;
  @override
  ConsumerState<NodeEditorDialog> createState() => _NodeEditorDialogState();
}

class _NodeEditorDialogState extends ConsumerState<NodeEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _server;
  late final TextEditingController _port;
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _obfsPassword = TextEditingController();
  final _url = TextEditingController();
  late final Map<String, TextEditingController> _advanced;
  final _cancellation = SubscriptionCancellation();
  late bool _subscription;
  String _method = shadowsocksMethods.first;
  String _transport = 'tcp';
  String _fingerprint = '';
  bool _insecure = false;
  bool _obfs = false;
  String _vmessSecurity = 'auto';
  String _packetEncoding = '';
  String _congestionControl = 'cubic';
  String _udpRelayMode = 'native';
  bool _globalPadding = false;
  bool _authenticatedLength = false;
  bool _zeroRtt = false;
  bool _disableSni = false;
  late NodeProtocol _protocol;
  bool _tls = false;
  bool _authenticate = false;
  bool _saving = false;
  bool _autoUpdate = true;
  bool _advancedExpanded = false;
  String? _error;
  SubscriptionReview? _review;
  SubscriptionContentException? _contentFailure;

  @override
  void initState() {
    super.initState();
    final node = widget.node;
    _name = TextEditingController(text: node?.name);
    _server = TextEditingController(text: node?.server);
    _port = TextEditingController(text: node?.port.toString());
    _protocol = node?.protocol ?? NodeProtocol.http;
    _tls = node?.tls ?? false;
    _authenticate = node?.credential.isNotEmpty ?? false;
    _subscription = widget.subscription;
    _url.addListener(_subscriptionUrlChanged);
    final o = node?.options ?? const NodeOptions();
    _method = o.method;
    _transport = o.transport;
    _fingerprint = o.fingerprint;
    _insecure = o.insecure;
    _obfs = o.obfs.isNotEmpty;
    _vmessSecurity = o.vmessSecurity;
    _packetEncoding = o.packetEncoding;
    _congestionControl = o.congestionControl;
    _udpRelayMode = o.udpOverStream ? 'stream' : o.udpRelayMode;
    _globalPadding = o.globalPadding;
    _authenticatedLength = o.authenticatedLength;
    _zeroRtt = o.zeroRttHandshake;
    _disableSni = o.disableSni;
    _advanced = {
      'sni': TextEditingController(text: o.serverName),
      'path': TextEditingController(text: o.path),
      'host': TextEditingController(text: o.host),
      'service': TextEditingController(text: o.serviceName),
      'flow': TextEditingController(text: o.flow),
      'publicKey': TextEditingController(text: o.realityPublicKey),
      'shortId': TextEditingController(text: o.realityShortId),
      'alpn': TextEditingController(text: o.alpn.join(',')),
      'certificateSha256': TextEditingController(text: o.certificateSha256),
      'up': TextEditingController(text: o.upMbps == 0 ? '' : '${o.upMbps}'),
      'down':
          TextEditingController(text: o.downMbps == 0 ? '' : '${o.downMbps}'),
      'ports': TextEditingController(
          text: o.serverPorts.join(',').replaceAll(':', '-')),
      'hop': TextEditingController(
          text: o.hopIntervalSeconds == 0 ? '' : '${o.hopIntervalSeconds}'),
      'alterId': TextEditingController(text: '${o.alterId}'),
      'heartbeat': TextEditingController(text: '${o.heartbeatMillis}'),
    };
  }

  void _subscriptionUrlChanged() {
    if (_review != null || _error != null || _contentFailure != null) {
      setState(() {
        _review = null;
        _error = null;
        _contentFailure = null;
      });
    }
  }

  @override
  void dispose() {
    _cancellation.cancel();
    _url.removeListener(_subscriptionUrlChanged);
    for (final controller in [
      _name,
      _server,
      _port,
      _username,
      _password,
      _obfsPassword,
      _url,
      ..._advanced.values
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
      _contentFailure = null;
    });
    try {
      if (_subscription) {
        final controller = ref.read(subscriptionControllerProvider.notifier);
        final review = _review;
        if (review == null) {
          await controller.importUrl(_url.text, _cancellation,
              autoUpdate: _autoUpdate);
        } else {
          await controller.acceptReview(review,
              cancellation: _cancellation, autoUpdate: _autoUpdate);
        }
      } else {
        await ref.read(nodeRepositoryProvider).save(NodeDraft(
            name: _name.text,
            protocol: _protocol,
            server: _server.text,
            port: int.parse(_port.text),
            tls: _tls,
            authenticate: _authenticate,
            username: _username.text,
            password: _password.text,
            obfsPassword: _obfs ? _obfsPassword.text : '',
            options: NodeOptions(
                method: _method,
                transport: _transport,
                fingerprint: _fingerprint,
                certificateSha256: normalizeCertificateSha256(
                    _advanced['certificateSha256']?.text ?? ''),
                insecure: _insecure,
                serverName: _advanced['sni']?.text.trim() ?? '',
                path: _advanced['path']?.text ?? '/',
                host: _advanced['host']?.text.trim() ?? '',
                serviceName: _advanced['service']?.text.trim() ?? '',
                flow: _advanced['flow']?.text.trim() ?? '',
                realityPublicKey: _advanced['publicKey']?.text.trim() ?? '',
                realityShortId: _advanced['shortId']?.text.trim() ?? '',
                alpn: (_advanced['alpn']?.text ?? '')
                    .split(',')
                    .map((v) => v.trim())
                    .where((v) => v.isNotEmpty)
                    .toList(),
                obfs: _obfs ? 'salamander' : '',
                upMbps: _integerOption('up'),
                downMbps: _integerOption('down'),
                serverPorts: parseHysteriaPorts(_advanced['ports']?.text ?? ''),
                hopIntervalSeconds: _integerOption('hop'),
                vmessSecurity: _vmessSecurity,
                alterId: _integerOption('alterId'),
                globalPadding: _globalPadding,
                authenticatedLength: _authenticatedLength,
                packetEncoding: _packetEncoding,
                congestionControl: _congestionControl,
                udpRelayMode:
                    _udpRelayMode == 'stream' ? 'native' : _udpRelayMode,
                udpOverStream: _udpRelayMode == 'stream',
                zeroRttHandshake: _zeroRtt,
                heartbeatMillis: _protocol == NodeProtocol.tuic
                    ? _integerOption('heartbeat')
                    : 10000,
                disableSni: _disableSni),
            original: widget.node));
      }
      if (mounted) Navigator.of(context).pop();
    } on SubscriptionReviewRequired catch (error) {
      if (mounted) {
        setState(() {
          _review = error.review;
          _saving = false;
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _error =
              error is NodeException ? error.message : '保存失败，请检查宿主与节点参数后重试';
          _saving = false;
          // A retry fetches again instead of reusing an expired/stale snapshot.
          _review = null;
          _contentFailure =
              error is SubscriptionContentException ? error : null;
        });
      }
    }
  }

  Future<void> _pasteSubscription() async {
    try {
      final value = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (!mounted || _saving || value == null) return;
      if (value.length > 4096) throw const NodeException('订阅地址超过长度限制');
      _url.text = value.trim();
      setState(() => _error = null);
    } on Exception catch (error) {
      if (mounted) {
        setState(() =>
            _error = error is NodeException ? error.message : '无法读取剪贴板，请手动粘贴');
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving || _subscription,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _cancellation.cancel();
      },
      child: AlertDialog(
        alignment: AppLayout.current == AppLayout.mobile
            ? Alignment.bottomCenter
            : Alignment.center,
        insetPadding: AppLayout.current == AppLayout.mobile
            ? EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top + 20)
            : const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: RainlinkColors.of(context).border)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 +
                (AppLayout.current == AppLayout.mobile
                    ? MediaQuery.viewPaddingOf(context).bottom
                    : 0)),
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: 22,
            height: 32 / 22,
            fontWeight: FontWeight.w500,
            fontVariations: const [FontVariation('wght', 500)]),
        title: Row(children: [
          Expanded(child: Text(widget.node == null ? '添加' : '编辑节点')),
          IconButton(
              tooltip: '关闭',
              onPressed: _saving && !_subscription
                  ? null
                  : () => Navigator.of(context).pop(),
              icon: const RainlinkIcon(RainlinkGlyph.close, size: 18)),
        ]),
        content: SizedBox(
            width: 472,
            child: SingleChildScrollView(
                child: Form(
                    key: _form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.node == null) ...[
                          RainlinkSegmentedControl<bool>(
                            segments: const [
                              RainlinkSegment(value: true, label: '订阅'),
                              RainlinkSegment(value: false, label: '单个节点'),
                            ],
                            selected: _subscription,
                            expanded: true,
                            enabled: !_saving,
                            onChanged: (selection) => setState(() {
                              _subscription = selection;
                              _error = null;
                              _review = null;
                              _contentFailure = null;
                            }),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_subscription) ...[
                          Text('订阅地址',
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 6),
                          TextFormField(
                              key: const ValueKey('subscription-url'),
                              controller: _url,
                              enabled: !_saving,
                              autocorrect: false,
                              enableSuggestions: false,
                              keyboardType: TextInputType.url,
                              decoration: const InputDecoration(
                                  hintText: '粘贴 https:// 订阅地址'),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? '请输入订阅地址'
                                  : null),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                              onPressed: _saving ? null : _pasteSubscription,
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 44)),
                              icon: const RainlinkIcon(RainlinkGlyph.copy,
                                  size: 16),
                              label: const Text('粘贴链接')),
                          const SizedBox(height: 12),
                          InkWell(
                              onTap: _saving
                                  ? null
                                  : () => setState(
                                      () => _autoUpdate = !_autoUpdate),
                              borderRadius: BorderRadius.circular(8),
                              child: Row(children: [
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text('自动更新',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge),
                                      Text('按服务商更新周期检查',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                    ])),
                                RainlinkSwitch(
                                    value: _autoUpdate,
                                    label: '自动更新订阅',
                                    onChanged: _saving
                                        ? null
                                        : (v) =>
                                            setState(() => _autoUpdate = v))
                              ])),
                          const SizedBox(height: 12),
                          Text('名称自动识别，导入后创建分组；流量与到期时间以服务商提供的信息为准。',
                              style: Theme.of(context).textTheme.bodySmall),
                          if (_review case final review?) ...[
                            const SizedBox(height: 16),
                            SubscriptionReviewPanel(
                                key: ObjectKey(review),
                                issues: review.document.issues,
                                skippedNodes: review.document.skippedNodes,
                                availableNodes: review.document.nodes.length,
                                pending: true),
                          ] else if (_contentFailure case final failure?) ...[
                            const SizedBox(height: 16),
                            SubscriptionReviewPanel(
                                issues: failure.issues,
                                skippedNodes: failure.skippedNodes,
                                availableNodes: 0),
                          ],
                        ] else ...[
                          Text('手动节点保存到「未分组」，选择后在概览连接。',
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 20),
                          TextFormField(
                              key: const ValueKey('node-name'),
                              controller: _name,
                              autofocus: true,
                              maxLength: 128,
                              enabled: !_saving,
                              decoration: const InputDecoration(
                                  labelText: '节点名称', counterText: ''),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? '请输入节点名称'
                                      : null),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<NodeProtocol>(
                              isExpanded: true,
                              icon: const RainlinkIcon(
                                  RainlinkGlyph.chevronDown,
                                  size: 16),
                              value: _protocol,
                              decoration:
                                  const InputDecoration(labelText: '协议'),
                              items: [
                                for (final value in NodeProtocol.values)
                                  DropdownMenuItem(
                                      value: value, child: Text(value.label))
                              ],
                              onChanged: _saving
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        setState(() {
                                          _protocol = value;
                                          _tls = [
                                            NodeProtocol.trojan,
                                            NodeProtocol.hysteria2,
                                            NodeProtocol.tuic
                                          ].contains(value);
                                          _transport =
                                              value.usesQuic ? 'quic' : 'tcp';
                                          _fingerprint = '';
                                          _insecure = false;
                                          _obfs = false;
                                          _vmessSecurity = 'auto';
                                          _packetEncoding = '';
                                          _congestionControl = 'cubic';
                                          _udpRelayMode = 'native';
                                          _globalPadding = false;
                                          _authenticatedLength = false;
                                          _zeroRtt = false;
                                          _disableSni = false;
                                          _username.clear();
                                          _password.clear();
                                          _obfsPassword.clear();
                                          for (final controller
                                              in _advanced.values) {
                                            controller.clear();
                                          }
                                          _advanced['path']?.text = '/';
                                          _advanced['alterId']?.text = '0';
                                          _advanced['heartbeat']?.text =
                                              '10000';
                                        });
                                      }
                                    }),
                          const SizedBox(height: 14),
                          if (_protocol == NodeProtocol.hysteria2) ...[
                            Text('QUIC · TLS 默认启用。填写服务商提供的认证密码。',
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 14),
                          ],
                          if (_protocol == NodeProtocol.tuic) ...[
                            Text('TUIC v5 · QUIC 与 TLS 默认启用。',
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 14),
                          ],
                          if (_protocol == NodeProtocol.vmess) ...[
                            DropdownButtonFormField<String>(
                                icon: const RainlinkIcon(
                                    RainlinkGlyph.chevronDown,
                                    size: 16),
                                value: _vmessSecurity,
                                decoration:
                                    const InputDecoration(labelText: '加密方式'),
                                items: [
                                  for (final value in vmessSecurityMethods)
                                    DropdownMenuItem(
                                        value: value, child: Text(value))
                                ],
                                onChanged: _saving
                                    ? null
                                    : (value) => setState(() =>
                                        _vmessSecurity = value ?? 'auto')),
                            const SizedBox(height: 14),
                          ],
                          if (_protocol == NodeProtocol.shadowsocks) ...[
                            DropdownButtonFormField<String>(
                                icon: const RainlinkIcon(
                                    RainlinkGlyph.chevronDown,
                                    size: 16),
                                value: _method,
                                isExpanded: true,
                                decoration:
                                    const InputDecoration(labelText: '加密方式'),
                                items: [
                                  for (final method in shadowsocksMethods)
                                    DropdownMenuItem(
                                        value: method, child: Text(method))
                                ],
                                onChanged: _saving
                                    ? null
                                    : (v) => setState(() => _method =
                                        v ?? shadowsocksMethods.first)),
                            const SizedBox(height: 14),
                          ],
                          TextFormField(
                              key: const ValueKey('node-server'),
                              controller: _server,
                              enabled: !_saving,
                              decoration: const InputDecoration(
                                  labelText: '服务器地址', hintText: '域名或 IP'),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? '请输入服务器地址'
                                      : null),
                          const SizedBox(height: 14),
                          TextFormField(
                              key: const ValueKey('node-port'),
                              controller: _port,
                              enabled: !_saving,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: '端口'),
                              validator: (value) {
                                final port = int.tryParse(value ?? '');
                                return port == null || port < 1 || port > 65535
                                    ? '请输入 1–65535 的端口'
                                    : null;
                              }),
                          const SizedBox(height: 14),
                          if (_protocol == NodeProtocol.http ||
                              _protocol == NodeProtocol.vless ||
                              _protocol == NodeProtocol.vmess)
                            CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                value: _tls,
                                onChanged: _saving
                                    ? null
                                    : (value) =>
                                        setState(() => _tls = value ?? false),
                                title: Text(_protocol == NodeProtocol.http
                                    ? '使用 TLS（HTTPS 代理）'
                                    : _protocol == NodeProtocol.vless
                                        ? '使用 TLS / Reality'
                                        : '使用 TLS')),
                          if (_protocol == NodeProtocol.http ||
                              _protocol == NodeProtocol.socks5)
                            CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                value: _authenticate,
                                onChanged: _saving
                                    ? null
                                    : (value) => setState(
                                        () => _authenticate = value ?? false),
                                title: const Text('需要用户名和密码')),
                          if (_authenticate ||
                              ![NodeProtocol.http, NodeProtocol.socks5]
                                  .contains(_protocol)) ...[
                            if ([
                              NodeProtocol.http,
                              NodeProtocol.socks5,
                              NodeProtocol.tuic
                            ].contains(_protocol)) ...[
                              TextFormField(
                                  key: const ValueKey('node-username'),
                                  controller: _username,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  enabled: !_saving,
                                  maxLength: 4096,
                                  decoration: InputDecoration(
                                      labelText: _protocol == NodeProtocol.tuic
                                          ? 'UUID'
                                          : '用户名',
                                      counterText: '')),
                              const SizedBox(height: 14),
                            ],
                            TextFormField(
                                key: const ValueKey('node-password'),
                                controller: _password,
                                obscureText: true,
                                enableSuggestions: false,
                                autocorrect: false,
                                enabled: !_saving,
                                maxLength: 4096,
                                decoration: InputDecoration(
                                    labelText: [
                                      NodeProtocol.vless,
                                      NodeProtocol.vmess
                                    ].contains(_protocol)
                                        ? 'UUID'
                                        : _protocol == NodeProtocol.tuic
                                            ? '密码（可选）'
                                            : '密码',
                                    counterText: '')),
                            const SizedBox(height: 8),
                            Text(
                                (widget.node?.credential.isNotEmpty ?? false) &&
                                        widget.node?.protocol == _protocol
                                    ? (_protocol == NodeProtocol.hysteria2 &&
                                            _obfs
                                        ? '认证与混淆密码同时留空可保留；修改任一密码时需重新填写两项。'
                                        : '凭据字段留空可保留已保存凭据。')
                                    : '凭据加密保存在当前设备。',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                          if (_tls ||
                              [
                                NodeProtocol.vless,
                                NodeProtocol.vmess,
                                NodeProtocol.trojan
                              ].contains(_protocol))
                            _advancedFields(context),
                        ],
                        if (_error case final error?) ...[
                          const SizedBox(height: 12),
                          Text(error,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ],
                      ],
                    )))),
        actions: [
          Row(children: [
            SizedBox(
                width: 96,
                child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                    onPressed: _saving && !_subscription
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(_saving && _subscription ? '取消导入' : '取消'))),
            const SizedBox(width: 12),
            Expanded(
                child: FilledButton.icon(
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    key: const ValueKey('save-node'),
                    onPressed: _saving ? null : _save,
                    icon: RainlinkIcon(
                        _subscription
                            ? RainlinkGlyph.download
                            : RainlinkGlyph.check,
                        size: 16),
                    label: Text(_saving
                        ? (_subscription ? '正在导入…' : '正在保存…')
                        : (_subscription
                            ? (_review == null ? '导入订阅' : '确认导入')
                            : '保存节点')))),
          ]),
        ],
      ));

  Widget _advancedFields(BuildContext context) => ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('高级选项'),
          onExpansionChanged: (expanded) =>
              setState(() => _advancedExpanded = expanded),
          trailing: AnimatedRotation(
              turns: _advancedExpanded ? 0.5 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
              child: const RainlinkIcon(RainlinkGlyph.chevronDown, size: 16)),
          children: [
            if (_protocol == NodeProtocol.vmess) ...[
              _optionField('alterId', 'Alter ID（0 使用 AEAD）', integer: true),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _globalPadding,
                  title: const Text('全局填充'),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _globalPadding = v ?? false)),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _authenticatedLength,
                  title: const Text('长度块加密'),
                  onChanged: _saving
                      ? null
                      : (v) =>
                          setState(() => _authenticatedLength = v ?? false)),
            ],
            if ([NodeProtocol.vless, NodeProtocol.vmess]
                .contains(_protocol)) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                  icon: const RainlinkIcon(RainlinkGlyph.chevronDown, size: 16),
                  value: _packetEncoding,
                  decoration: const InputDecoration(labelText: 'UDP 包编码'),
                  items: [
                    for (final value in udpPacketEncodings)
                      DropdownMenuItem(
                          value: value,
                          child: Text(value.isEmpty ? '默认' : value))
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _packetEncoding = v ?? '')),
              const SizedBox(height: 12),
            ],
            if ([NodeProtocol.vless, NodeProtocol.vmess, NodeProtocol.trojan]
                .contains(_protocol)) ...[
              DropdownButtonFormField<String>(
                  icon: const RainlinkIcon(RainlinkGlyph.chevronDown, size: 16),
                  value: _transport,
                  decoration: const InputDecoration(labelText: '传输方式'),
                  items: const [
                    DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                    DropdownMenuItem(value: 'ws', child: Text('WebSocket')),
                    DropdownMenuItem(value: 'grpc', child: Text('gRPC'))
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _transport = v ?? 'tcp')),
              if (_transport == 'ws') ...[
                _optionField('path', 'WebSocket 路径'),
                _optionField('host', 'Host（可选）')
              ],
              if (_transport == 'grpc') _optionField('service', 'gRPC 服务名称'),
            ],
            if (_tls) ...[
              _optionField('sni', '服务器名称 SNI（可选）'),
              _optionField('alpn', 'ALPN（可选，逗号分隔）'),
              const SizedBox(height: 12),
              if (!_protocol.usesQuic)
                DropdownButtonFormField<String>(
                    icon:
                        const RainlinkIcon(RainlinkGlyph.chevronDown, size: 16),
                    value: _fingerprint,
                    decoration: const InputDecoration(labelText: 'TLS 指纹'),
                    items: [
                      for (final value in tlsFingerprints)
                        DropdownMenuItem(
                            value: value,
                            child: Text(value.isEmpty ? '默认' : value))
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _fingerprint = v ?? '')),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _insecure,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _insecure = v ?? false),
                  title: const Text('跳过证书验证')),
              if (_protocol == NodeProtocol.vless) ...[
                _optionField('flow', 'Flow（可选，如 xtls-rprx-vision）'),
                _optionField('publicKey', 'Reality 公钥（可选）'),
                _optionField('shortId', 'Reality Short ID（可选）'),
              ],
            ],
            if (_protocol.usesQuic) ...[
              _optionField('certificateSha256', '证书 SHA-256 指纹（可选）'),
              Text('填写指纹后始终校验证书指纹，优先于跳过证书验证。',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (_protocol == NodeProtocol.tuic) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                  icon: const RainlinkIcon(RainlinkGlyph.chevronDown, size: 16),
                  value: _congestionControl,
                  decoration: const InputDecoration(labelText: '拥塞控制'),
                  items: [
                    for (final value in tuicCongestionControls)
                      DropdownMenuItem(value: value, child: Text(value))
                  ],
                  onChanged: _saving
                      ? null
                      : (v) =>
                          setState(() => _congestionControl = v ?? 'cubic')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                  icon: const RainlinkIcon(RainlinkGlyph.chevronDown, size: 16),
                  value: _udpRelayMode,
                  decoration: const InputDecoration(labelText: 'UDP 中继模式'),
                  items: const [
                    DropdownMenuItem(value: 'native', child: Text('原生 UDP')),
                    DropdownMenuItem(value: 'quic', child: Text('QUIC 流')),
                    DropdownMenuItem(
                        value: 'stream',
                        child: Text('UDP over Stream（需服务端支持）')),
                  ],
                  isExpanded: true,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _udpRelayMode = v ?? 'native')),
              _optionField('heartbeat', '心跳间隔（毫秒，1000–3600000）', integer: true),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _disableSni,
                  title: const Text('不发送 SNI'),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _disableSni = v ?? false)),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _zeroRtt,
                  title: const Text('0-RTT 握手'),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _zeroRtt = v ?? false)),
            ],
            if (_protocol == NodeProtocol.hysteria2) ...[
              _optionField('up', '上传带宽 Mbps（可选，留空自动）', integer: true),
              _optionField('down', '下载带宽 Mbps（可选，留空自动）', integer: true),
              _optionField('ports', '跳跃端口（可选，如 443,20000-30000）'),
              _optionField('hop', '端口跳跃间隔 秒（可选）', integer: true),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _obfs,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _obfs = value ?? false),
                  title: const Text('启用 Salamander 混淆')),
              if (_obfs)
                TextFormField(
                    key: const ValueKey('node-obfs-password'),
                    controller: _obfsPassword,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !_saving,
                    maxLength: 4096,
                    decoration: const InputDecoration(
                        labelText: '混淆密码', counterText: '')),
            ],
          ]);

  int _integerOption(String key) {
    final input = _advanced[key]?.text.trim() ?? '';
    if (input.isEmpty) return 0;
    final value = int.tryParse(input);
    if (value == null) throw const NodeException('请输入有效的整数参数');
    return value;
  }

  Widget _optionField(String key, String label, {bool integer = false}) =>
      Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextFormField(
              key: ValueKey('node-option-$key'),
              controller: _advanced[key],
              enabled: !_saving,
              keyboardType: integer ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(labelText: label)));
}
