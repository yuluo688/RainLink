import 'package:flutter/material.dart';

import '../theme/rainlink_colors.dart';
import 'rainlink_icon.dart';

class TelemetryToolbar extends StatelessWidget {
  const TelemetryToolbar(
      {required this.search, required this.controls, super.key});
  final Widget search;
  final List<Widget> controls;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final actions = Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: controls);
        final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
        if (constraints.maxWidth < 1020 * textScale) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 8),
                actions,
              ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          SizedBox(width: 360, child: search),
          const Spacer(),
          actions,
        ]);
      });
}

class TelemetrySearchField extends StatelessWidget {
  const TelemetrySearchField(
      {required this.controller,
      required this.label,
      required this.hint,
      required this.onChanged,
      super.key});
  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
              hintText: hint,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 40, minHeight: 40),
              prefixIcon: const Padding(
                  padding: EdgeInsets.all(12),
                  child: RainlinkIcon(RainlinkGlyph.search, size: 16)),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      icon: const RainlinkIcon(RainlinkGlyph.close, size: 16),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    )),
        ),
      ]);
}

class TelemetryNotice extends StatelessWidget {
  const TelemetryNotice(
      {required this.message, this.error = false, this.onRetry, super.key});
  final String message;
  final bool error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(
              child: Text(message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: error ? RainlinkColors.of(context).error : null))),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('重试')),
        ]),
      );
}

class TelemetryEmptyState extends StatelessWidget {
  const TelemetryEmptyState(
      {required this.glyph,
      required this.title,
      required this.description,
      super.key});
  final RainlinkGlyph glyph;
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            RainlinkIcon(glyph,
                size: 24, color: RainlinkColors.of(context).muted),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ])));
}

String telemetryTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String telemetryDuration(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 99999999);
  if (seconds < 60) return '$seconds 秒';
  if (seconds < 3600) return '${seconds ~/ 60} 分 ${seconds % 60} 秒';
  return '${seconds ~/ 3600} 小时 ${(seconds % 3600) ~/ 60} 分';
}
