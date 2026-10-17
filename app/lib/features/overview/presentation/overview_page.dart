import 'package:flutter/material.dart';

import '../../../design_system/layout/app_layout.dart';
import 'desktop_overview.dart';
import 'mobile_overview.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) => switch (AppLayout.current) {
        AppLayout.desktop => const DesktopOverview(),
        AppLayout.mobile => const MobileOverview(),
      };
}
