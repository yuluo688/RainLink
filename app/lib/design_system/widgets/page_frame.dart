import 'package:flutter/material.dart';

import '../layout/app_layout.dart';
import '../layout/desktop_page_frame.dart';
import '../layout/mobile_page_frame.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({
    required this.title,
    required this.description,
    required this.child,
    this.actions = const [],
    this.leading,
    this.showMobileNavigationButton = true,
    this.scrollable = true,
    this.padding,
    super.key,
  });

  final String title;
  final String description;
  final Widget child;
  final List<Widget> actions;
  final Widget? leading;
  final bool showMobileNavigationButton;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return switch (AppLayout.current) {
      AppLayout.desktop => DesktopPageFrame(
          title: title,
          description: description,
          actions: actions,
          leading: leading,
          scrollable: scrollable,
          padding: padding,
          child: child,
        ),
      AppLayout.mobile => MobilePageFrame(
          title: title,
          description: description,
          actions: actions,
          leading: leading,
          showNavigationButton: showMobileNavigationButton,
          scrollable: scrollable,
          padding: padding,
          child: child,
        ),
    };
  }
}
