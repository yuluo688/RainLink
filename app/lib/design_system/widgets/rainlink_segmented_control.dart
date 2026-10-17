import 'package:flutter/material.dart';

import '../theme/rainlink_colors.dart';
import '../theme/rainlink_density.dart';

class RainlinkSegment<T> {
  const RainlinkSegment({required this.value, required this.label});
  final T value;
  final String label;
}

class RainlinkSegmentedControl<T> extends StatelessWidget {
  const RainlinkSegmentedControl({
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.expanded = false,
    this.enabled = true,
    super.key,
  });

  final List<RainlinkSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool expanded;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < segments.length; index++) ...[
          if (index > 0) const SizedBox(width: 4),
          if (expanded)
            Expanded(child: _segment(context, colors, segments[index]))
          else
            _segment(context, colors, segments[index]),
        ],
      ],
    );
  }

  Widget _segment(BuildContext context, RainlinkColors colors,
          RainlinkSegment<T> segment) =>
      Semantics(
        enabled: enabled,
        selected: segment.value == selected,
        inMutuallyExclusiveGroup: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? () => onChanged(segment.value) : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Ink(
                decoration: BoxDecoration(
                  color: segment.value == selected
                      ? colors.primarySurface
                      : colors.raised,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      minWidth: 64,
                      minHeight: RainlinkDensity.of(context).segmentHeight),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(segment.label,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: segment.value == selected
                                        ? colors.primary
                                        : colors.secondary,
                                  )),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
