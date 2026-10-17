import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/design_system/theme/rainlink_theme.dart';
import 'package:rainlink/design_system/widgets/rainlink_switch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every bundled Figma SVG decodes and paints visible pixels', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets().where((path) => path.endsWith('.svg'));
    // Includes 36 interface icons, the brand mark and seven country flags.
    expect(assets, hasLength(44));
    for (final asset in assets) {
      final picture = await vg.loadPicture(SvgAssetLoader(asset), null);
      final image = await picture.picture.toImage(40, 40);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        expect(data, isNotNull, reason: asset);
        final pixels = data?.buffer.asUint8List() ?? Uint8List(0);
        final hasInk = Iterable<int>.generate(pixels.length ~/ 4)
            .any((index) => pixels[index * 4 + 3] > 0);
        expect(hasInk, isTrue, reason: 'Empty native SVG export: $asset');
      } finally {
        image.dispose();
        picture.picture.dispose();
      }
    }
  });

  testWidgets('compact switch preserves hit target, keyboard and semantics',
      (tester) async {
    var value = false;
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MaterialApp(
        theme: buildRainlinkTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
                builder: (context, setState) => RainlinkSwitch(
                      label: '系统代理',
                      value: value,
                      onChanged: (next) => setState(() => value = next),
                    )),
          ),
        ),
      ));
      final control = find.byType(RainlinkSwitch);
      expect(tester.getSize(control), const Size(44, 44));
      expect(
          tester.getSemantics(control),
          matchesSemantics(
            label: '系统代理',
            hasEnabledState: true,
            isEnabled: true,
            hasToggledState: true,
            isToggled: false,
            hasTapAction: true,
          ));
      // The edge of the hit region lies outside the visible 36 × 22 track.
      await tester.tapAt(tester.getTopLeft(control) + const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(value, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(value, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'unavailable capture switch cannot toggle by pointer or semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MaterialApp(
        theme: buildRainlinkTheme(Brightness.light),
        home: const Scaffold(
            body: Center(
                child: RainlinkSwitch(
          label: 'TUN 模式',
          value: false,
          onChanged: null,
        ))),
      ));
      final control = find.byType(RainlinkSwitch);
      expect(
          tester.getSemantics(control),
          matchesSemantics(
            label: 'TUN 模式',
            hasEnabledState: true,
            isEnabled: false,
            hasToggledState: true,
            isToggled: false,
          ));
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(tester.widget<RainlinkSwitch>(control).value, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
