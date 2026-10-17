import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/rainlink_colors.dart';

/// A lightweight chart for the bounded telemetry samples held by the client.
class RainlinkChartSeries {
  const RainlinkChartSeries(this.values, this.color, {this.fill = false});
  final List<double?> values;
  final Color color;
  final bool fill;
}

class RainlinkLineChart extends StatelessWidget {
  const RainlinkLineChart({
    required this.series,
    this.emptyLabel = '暂无数据',
    this.selectedIndex,
    super.key,
  });

  final List<RainlinkChartSeries> series;
  final String emptyLabel;
  final int? selectedIndex;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    return CustomPaint(
      painter: _ChartPainter(series, colors.border, selectedIndex),
      child: series.every((line) => line.values.whereType<double>().isEmpty)
          ? Center(
              child: Text(emptyLabel,
                  style: Theme.of(context).textTheme.bodySmall))
          : const SizedBox.expand(),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.series, this.gridColor, this.selectedIndex);
  final List<RainlinkChartSeries> series;
  final Color gridColor;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var row = 0; row <= 3; row++) {
      final y = 5 + (size.height - 10) * row / 3;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + 3, size.width), y), grid);
      }
    }
    final maximum = series
        .expand((line) => line.values)
        .whereType<double>()
        .fold<double>(1, (maximum, value) => math.max(maximum, value));
    for (final line in series) {
      if (line.values.isEmpty) continue;
      final path = Path();
      Offset? last;
      var inSegment = false;
      for (var i = 0; i < line.values.length; i++) {
        final value = line.values[i];
        if (value == null) {
          inSegment = false;
          continue;
        }
        final x = line.values.length == 1
            ? size.width / 2
            : size.width * i / (line.values.length - 1);
        final y = size.height - 6 - value / maximum * (size.height - 18);
        last = Offset(x, y);
        if (!inSegment) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        inSegment = true;
        final isolated = (i == 0 || line.values[i - 1] == null) &&
            (i == line.values.length - 1 || line.values[i + 1] == null);
        if (isolated || selectedIndex == i) {
          canvas.drawCircle(
              last, selectedIndex == i ? 4 : 3, Paint()..color = line.color);
        }
      }
      if (line.fill && line.values.length > 1 && !line.values.contains(null)) {
        final area = Path.from(path)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(
            area,
            Paint()
              ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    line.color.withValues(alpha: .16),
                    line.color.withValues(alpha: 0)
                  ]).createShader(Offset.zero & size));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = line.color
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 2);
      if (line.values.length == 1 && last != null) {
        canvas.drawCircle(last, 3, Paint()..color = line.color);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChartPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.selectedIndex != selectedIndex;
}
