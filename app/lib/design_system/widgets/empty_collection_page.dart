import 'package:flutter/material.dart';

import '../layout/app_layout.dart';
import '../layout/desktop_collection_layout.dart';
import '../layout/mobile_collection_layout.dart';
import 'empty_state.dart';
import 'page_frame.dart';
import 'rainlink_icon.dart';

class EmptyCollectionPage extends StatelessWidget {
  const EmptyCollectionPage({
    required this.title,
    required this.description,
    required this.icon,
    required this.emptyTitle,
    required this.emptyDescription,
    required this.columns,
    this.actions = const [],
    this.toolbar,
    this.columnFlexes,
    super.key,
  });

  final String title;
  final String description;
  final RainlinkGlyph icon;
  final String emptyTitle;
  final String emptyDescription;
  final List<String> columns;
  final List<Widget> actions;
  final Widget? toolbar;
  final List<int>? columnFlexes;

  @override
  Widget build(BuildContext context) {
    assert(columnFlexes == null || columnFlexes?.length == columns.length);
    final emptyState = EmptyState(
        icon: icon, title: emptyTitle, description: emptyDescription);
    return PageFrame(
      title: title,
      description: description,
      actions: actions,
      child: switch (AppLayout.current) {
        AppLayout.desktop => DesktopCollectionLayout(
            columns: columns,
            columnFlexes: columnFlexes,
            toolbar: toolbar,
            emptyState: emptyState,
          ),
        AppLayout.mobile =>
          MobileCollectionLayout(toolbar: toolbar, emptyState: emptyState),
      },
    );
  }
}
