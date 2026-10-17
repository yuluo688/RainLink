import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/groups/group_providers.dart';
import '../../../domain/nodes/proxy_node.dart';
import '../../groups/presentation/group_details_dialog.dart';

Future<void> moveNodeDialog(
    BuildContext context, WidgetRef ref, ProxyNode node) async {
  final repository = ref.read(groupRepositoryProvider);
  final groups = await repository.watchGroups().first;
  if (!context.mounted) return;
  var id = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(title: const Text('移入分组'), children: [
            for (final group in groups)
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, group.id),
                  child: Text(group.name)),
            SimpleDialogOption(
                onPressed: () => Navigator.pop(context, '@new'),
                child: const Text('＋ 新建分组')),
            SimpleDialogOption(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
          ]));
  if (id == null || !context.mounted) return;
  if (id == '@new') {
    final name = await showGroupNameDialog(context);
    if (name == null) return;
    id = await repository.createManual(name);
  }
  await repository.moveUngrouped(node.id, id);
}
