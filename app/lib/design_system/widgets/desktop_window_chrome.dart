import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform/window/desktop_window.dart';
import '../theme/rainlink_colors.dart';

const desktopHeaderHeight = 56.0;
const _captionButtonSize = Size(40, 32);
const _captionAnimationDuration = Duration(milliseconds: 120);

Future<void> _performWindowAction(BuildContext context, String failureMessage,
    Future<void> Function() action) async {
  try {
    await action();
  } on Exception catch (error, stackTrace) {
    if (error is! PlatformException && error is! TimeoutException) rethrow;
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'RainLink window controls',
      context: ErrorDescription(failureMessage),
    ));
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(failureMessage)),
      );
    }
  }
}

/// Only caption areas handle dragging, so content and window buttons keep taps.
class DesktopWindowDragArea extends StatelessWidget {
  const DesktopWindowDragArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!usesCustomWindowChrome) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => unawaited(
          _performWindowAction(context, '无法移动窗口，请重试。', dragDesktopWindow)),
      onDoubleTap: () => unawaited(_performWindowAction(
          context, '无法调整窗口大小，请重试。', toggleDesktopWindowMaximized)),
      onSecondaryTap: supportsDesktopWindowMenu
          ? () => unawaited(_performWindowAction(
              context, '无法打开窗口菜单，请重试。', showDesktopWindowMenu))
          : null,
      child: child,
    );
  }
}

class DesktopWindowControls extends StatefulWidget {
  const DesktopWindowControls({super.key});

  @override
  State<DesktopWindowControls> createState() => _DesktopWindowControlsState();
}

class _DesktopWindowControlsState extends State<DesktopWindowControls> {
  final _controller = DesktopWindowController();

  @override
  void initState() {
    super.initState();
    if (usesCustomWindowChrome) unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
    } on Exception catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'RainLink window state',
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!usesCustomWindowChrome) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final colors = RainlinkColors.of(context);
        return SizedBox(
          height: desktopHeaderHeight,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 1, height: 20, color: colors.border),
            const SizedBox(width: 12),
            _CaptionButton(
              label: '最小化',
              glyph: _CaptionGlyph.minimize,
              focused: _controller.focused,
              onPressed: () => unawaited(_performWindowAction(
                  context, '无法最小化窗口，请重试。', _controller.minimize)),
            ),
            const SizedBox(width: 4),
            _CaptionButton(
              label: _controller.maximized ? '还原窗口' : '最大化',
              glyph: _controller.maximized
                  ? _CaptionGlyph.restore
                  : _CaptionGlyph.maximize,
              focused: _controller.focused,
              onPressed: () => unawaited(_performWindowAction(
                  context, '无法调整窗口大小，请重试。', _controller.toggleMaximized)),
            ),
            const SizedBox(width: 4),
            _CaptionButton(
              label: '关闭窗口',
              glyph: _CaptionGlyph.close,
              focused: _controller.focused,
              onPressed: () => unawaited(_performWindowAction(
                  context, '无法关闭窗口，请重试。', _controller.close)),
            ),
            const SizedBox(width: 12),
          ]),
        );
      },
    );
  }
}

enum _CaptionGlyph { minimize, maximize, restore, close }

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.label,
    required this.glyph,
    required this.focused,
    required this.onPressed,
  });

  final String label;
  final _CaptionGlyph glyph;
  final bool focused;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    final isClose = glyph == _CaptionGlyph.close;
    return IconButton(
      key: ValueKey('window-${isClose ? 'close' : glyph.name}'),
      tooltip: label,
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(_captionButtonSize),
        maximumSize: const WidgetStatePropertyAll(_captionButtonSize),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        animationDuration: _captionAnimationDuration,
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        side: WidgetStateProperty.resolveWith((states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? colors.primary
                : Colors.transparent)),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return isClose ? colors.error.withValues(alpha: .2) : colors.border;
          }
          if (states.contains(WidgetState.hovered)) {
            return isClose ? colors.error.withValues(alpha: .12) : colors.hover;
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed)) {
            return isClose ? colors.error : colors.text;
          }
          return focused ? colors.secondary : colors.muted;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      icon: Builder(builder: (context) {
        return CustomPaint(
          size: const Size.square(14),
          painter: _CaptionGlyphPainter(
              glyph, IconTheme.of(context).color ?? colors.secondary),
        );
      }),
    );
  }
}

class _CaptionGlyphPainter extends CustomPainter {
  const _CaptionGlyphPainter(this.glyph, this.color);

  final _CaptionGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    switch (glyph) {
      case _CaptionGlyph.minimize:
        canvas.drawLine(const Offset(2, 7), const Offset(12, 7), paint);
      case _CaptionGlyph.maximize:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(2, 2, 10, 10), const Radius.circular(1.5)),
            paint);
      case _CaptionGlyph.restore:
        canvas.drawPath(
            Path()
              ..moveTo(5, 3)
              ..lineTo(5, 1.5)
              ..lineTo(12.5, 1.5)
              ..lineTo(12.5, 9)
              ..lineTo(11, 9),
            paint);
        canvas.drawRRect(
            RRect.fromRectAndRadius(const Rect.fromLTWH(1.5, 4, 8.5, 8.5),
                const Radius.circular(1)),
            paint);
      case _CaptionGlyph.close:
        canvas.drawLine(const Offset(3, 3), const Offset(11, 11), paint);
        canvas.drawLine(const Offset(11, 3), const Offset(3, 11), paint);
    }
  }

  @override
  bool shouldRepaint(_CaptionGlyphPainter oldDelegate) =>
      glyph != oldDelegate.glyph || color != oldDelegate.color;
}
