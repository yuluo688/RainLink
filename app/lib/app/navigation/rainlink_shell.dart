import 'package:flutter/material.dart';

import '../../design_system/layout/app_layout.dart';
import 'app_destination.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

class RainlinkShell extends StatelessWidget {
  const RainlinkShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final selected = AppDestination.forPath(location);
    return switch (AppLayout.current) {
      AppLayout.desktop => DesktopShell(selected: selected, child: child),
      AppLayout.mobile => MobileShell(selected: selected, child: child),
    };
  }
}
