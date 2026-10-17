import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/widgets/rainlink_icon.dart';
import 'app_destination.dart';

class MobileShell extends StatelessWidget {
  const MobileShell({required this.selected, required this.child, super.key});
  final AppDestination selected;
  final Widget child;

  static const destinations = [
    AppDestination.overview,
    AppDestination.nodes,
    AppDestination.groups,
    AppDestination.traffic,
    AppDestination.settings,
  ];

  @override
  Widget build(BuildContext context) {
    final index = destinations.indexOf(selected);
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
            child: ListView(children: [
          for (final destination in AppDestination.values)
            ListTile(
              leading: RainlinkIcon(destination.icon),
              title: Text(destination.label),
              selected: destination == selected,
              onTap: () {
                Navigator.of(context).pop();
                context.go(destination.path);
              },
            ),
        ])),
      ),
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        indicatorColor: Colors.transparent,
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (value) => context.go(destinations[value].path),
        destinations: [
          for (final destination in destinations)
            NavigationDestination(
                icon: RainlinkIcon(destination.icon),
                label: destination == AppDestination.overview
                    ? '首页'
                    : destination.label),
        ],
      ),
    );
  }
}
