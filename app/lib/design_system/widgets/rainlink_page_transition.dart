import 'package:flutter/material.dart';

/// A short entrance for the content pane, without moving the app navigation.
class RainlinkPageTransition extends StatelessWidget {
  const RainlinkPageTransition({
    required this.animation,
    required this.child,
    super.key,
  });

  static const duration = Duration(milliseconds: 180);
  static const _entranceOffset = 8.0;

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final progress = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return ClipRect(
      // Keep a solid canvas so the previous page's text cannot show through
      // the incoming page, especially during rapid sidebar navigation.
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: reduceMotion
            ? child
            : FadeTransition(
                opacity: progress,
                child: AnimatedBuilder(
                  animation: progress,
                  child: child,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, _entranceOffset * (1 - progress.value)),
                    child: child,
                  ),
                ),
              ),
      ),
    );
  }
}
