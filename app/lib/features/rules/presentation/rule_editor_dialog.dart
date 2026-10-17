import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/groups/group_providers.dart';
import '../../../application/chains/chain_providers.dart';
import '../../../application/nodes/node_providers.dart';
import '../../../application/routing/routing_providers.dart';
import '../../../application/routing/route_target_info.dart';
import '../../../domain/identity/record_id.dart';
import '../../../domain/routing/route_rules.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../design_system/widgets/rainlink_switch.dart';

Future<void> showRuleEditor(BuildContext context, RouteRuleSet rules,
        [RouteRule? rule]) =>
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RuleEditorDialog(ruleSet: rules, original: rule));

class RuleEditorDialog extends ConsumerStatefulWidget {
  const RuleEditorDialog({required this.ruleSet, this.original, super.key});
  final RouteRuleSet ruleSet;
  final RouteRule? original;
  @override
  ConsumerState<RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends ConsumerState<RuleEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final _value = TextEditingController(text: widget.original?.value ?? '');
  late final String _id = widget.original?.id ?? newRecordId();
  late RouteRuleKind _kind =
      widget.original?.kind ?? RouteRuleKind.domainSuffix;
  late String _target = widget.original?.target.key ?? 'proxy';
  late bool _enabled = widget.original?.enabled ?? true;
  String _error = '';

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final saved = await ref.read(rulesControllerProvider.notifier).upsert(
        widget.ruleSet,
        RouteRule(
            id: _id,
            kind: _kind,
            value: _kind == RouteRuleKind.match ? '' : _value.text,
            target: RouteTarget.parse(_target),
            enabled: _enabled));
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => _error = ref.read(rulesControllerProvider).error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy =
        ref.watch(rulesControllerProvider.select((state) => state.saving));
    final groups = ref.watch(groupsProvider).valueOrNull ?? [];
    final nodes = ref.watch(nodesProvider).valueOrNull ?? [];
    final chains = ref.watch(chainsProvider).valueOrNull ?? [];
    final options = <String, String>{
      'proxy': '当前所选目标',
      'direct': '直连',
      'reject': '拦截',
      for (final group in groups) 'group:${group.id}': '分组 · ${group.name}',
      for (final node in nodes
          .where((node) => !node.hidden || _target == 'node:${node.id}'))
        'node:${node.id}': '节点 · ${node.name}${node.hidden ? '（已隐藏）' : ''}',
      for (final chain in chains) 'chain:${chain.id}': '代理链 · ${chain.name}',
    };
    if (!options.containsKey(_target)) {
      options[_target] =
          routeTargetLabel(RouteTarget.parse(_target), groups, nodes, chains);
    }
    final fallback = widget.original?.kind == RouteRuleKind.match;
    return PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: Row(children: [
            Expanded(child: Text(widget.original == null ? '添加规则' : '编辑规则')),
            IconButton(
                tooltip: '关闭',
                onPressed: busy ? null : () => Navigator.pop(context),
                icon: const RainlinkIcon(RainlinkGlyph.close, size: 18))
          ]),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<RouteRuleKind>(
                                style: Theme.of(context).textTheme.bodyMedium,
                                icon: const RainlinkIcon(
                                    RainlinkGlyph.chevronDown,
                                    size: 16),
                                value: _kind,
                                isExpanded: true,
                                decoration:
                                    const InputDecoration(labelText: '规则类型'),
                                items: [
                                  for (final kind in RouteRuleKind.values.where(
                                      (kind) => fallback
                                          ? kind == RouteRuleKind.match
                                          : kind != RouteRuleKind.match))
                                    DropdownMenuItem(
                                        value: kind,
                                        child: Text(
                                            '${kind.label} · ${kind.wireName}'))
                                ],
                                onChanged: busy || fallback
                                    ? null
                                    : (kind) {
                                        if (kind != null) {
                                          setState(() => _kind = kind);
                                        }
                                      }),
                            if (_kind != RouteRuleKind.match) ...[
                              const SizedBox(height: 18),
                              TextFormField(
                                  key: const ValueKey('rule-value'),
                                  controller: _value,
                                  enabled: !busy,
                                  autofocus: true,
                                  decoration: InputDecoration(
                                      labelText: '匹配条件',
                                      hintText: _kind == RouteRuleKind.ipCidr
                                          ? '192.168.0.0/16'
                                          : 'example.com',
                                      helperText:
                                          _kind == RouteRuleKind.domainSuffix
                                              ? '匹配此域名及其所有子域名'
                                              : _kind == RouteRuleKind.domain
                                                  ? '仅匹配完整域名'
                                                  : '支持 IPv4 和 IPv6，将自动归一化网段'),
                                  validator: (value) {
                                    try {
                                      normalizeRuleValue(_kind, value ?? '');
                                      return null;
                                    } on RoutingException catch (error) {
                                      return error.message;
                                    }
                                  }),
                            ] else ...[
                              const SizedBox(height: 12),
                              const Text('所有其他请求 · 兜底规则固定在最后。')
                            ],
                            const SizedBox(height: 18),
                            DropdownButtonFormField<String>(
                                style: Theme.of(context).textTheme.bodyMedium,
                                icon: const RainlinkIcon(
                                    RainlinkGlyph.chevronDown,
                                    size: 16),
                                key: const ValueKey('rule-target'),
                                value: _target,
                                isExpanded: true,
                                menuMaxHeight: 320,
                                decoration: const InputDecoration(
                                    labelText: '出站目标',
                                    helperMaxLines: 3,
                                    helperText: '分组使用该组上次选中的节点；尚未选择则使用首个节点'),
                                items: [
                                  for (final option in options.entries)
                                    DropdownMenuItem(
                                        value: option.key,
                                        child: Text(option.value,
                                            overflow: TextOverflow.ellipsis))
                                ],
                                onChanged: busy
                                    ? null
                                    : (value) {
                                        if (value != null) {
                                          setState(() => _target = value);
                                        }
                                      }),
                            if (!fallback) ...[
                              const SizedBox(height: 12),
                              Row(children: [
                                const Expanded(child: Text('启用此规则')),
                                RainlinkSwitch(
                                    value: _enabled,
                                    label: '启用此规则',
                                    onChanged: busy
                                        ? null
                                        : (value) =>
                                            setState(() => _enabled = value)),
                              ])
                            ],
                            if (_error.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(_error,
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error))
                            ],
                          ])))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                key: const ValueKey('save-rule'),
                onPressed: busy ? null : _save,
                child: Text(busy ? '校验并保存…' : '保存规则'))
          ],
        ));
  }
}
