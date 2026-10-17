import 'package:flutter/material.dart';

import '../theme/rainlink_colors.dart';

/// Figma's 36 × 22 switch with a 44 × 44 pointer and keyboard target.
class RainlinkSwitch extends StatelessWidget {
  const RainlinkSwitch({
    required this.value,
    required this.onChanged,
    required this.label,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    final enabled = onChanged != null;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140);
    final toggle = enabled ? () => onChanged?.call(!value) : null;
    return Semantics(
      label: label,
      toggled: value,
      enabled: enabled,
      onTap: toggle,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 44,
          height: 44,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: toggle,
              borderRadius: BorderRadius.circular(10),
              focusColor: colors.primarySurface,
              hoverColor: colors.hover,
              child: Center(
                child: AnimatedContainer(
                  duration: duration,
                  width: 36,
                  height: 22,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: value ? colors.primary : colors.border,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: AnimatedAlign(
                    duration: duration,
                    alignment:
                        value ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: value
                            ? colors.onPrimary
                            : enabled
                                ? colors.secondary
                                : colors.muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
