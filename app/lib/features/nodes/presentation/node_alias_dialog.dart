import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/nodes/node_providers.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../domain/nodes/proxy_node.dart';

Future<void> showNodeAliasDialog(BuildContext context, ProxyNode node) =>
    showDialog<void>(
        context: context, builder: (_) => _AliasDialog(node: node));

class _AliasDialog extends ConsumerStatefulWidget {
  const _AliasDialog({required this.node});
  final ProxyNode node;
  @override
  ConsumerState<_AliasDialog> createState() => _AliasDialogState();
}

class _AliasDialogState extends ConsumerState<_AliasDialog> {
  late final _name =
      TextEditingController(text: widget.node.hasAlias ? widget.node.name : '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(nodeOverridesRepositoryProvider)
          .setAlias(widget.node.id, _name.text);
      if (mounted) Navigator.pop(context);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is NodeException ? error.message : '别名保存失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
          title: Row(children: [
            const Expanded(child: Text('本地别名')),
            IconButton(
                tooltip: '关闭',
                onPressed: _saving ? null : () => Navigator.pop(context),
                icon: const RainlinkIcon(RainlinkGlyph.close, size: 18)),
          ]),
          content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Text('原名：${widget.node.sourceName}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 16),
                    TextField(
                        key: const ValueKey('node-alias'),
                        controller: _name,
                        enabled: !_saving,
                        autofocus: true,
                        maxLength: 128,
                        onSubmitted: (_) => _save(),
                        decoration: InputDecoration(
                            labelText: '别名',
                            hintText: '留空恢复订阅名称',
                            errorText: _error,
                            helperText: '仅在本机显示，订阅更新后保留。')),
                  ]))),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                key: const ValueKey('save-node-alias'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存')),
          ]));
}
