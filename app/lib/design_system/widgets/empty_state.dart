import 'package:flutter/material.dart';

import '../theme/rainlink_colors.dart';
import 'rainlink_icon.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    super.key,
  });

  final RainlinkGlyph icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration:
                    BoxDecoration(color: colors.raised, shape: BoxShape.circle),
                child: RainlinkIcon(icon, size: 28, color: colors.muted),
              ),
              const SizedBox(height: 20),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(description,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
              if (action != null) ...[
                const SizedBox(height: 24),
                action ?? const SizedBox.shrink(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
