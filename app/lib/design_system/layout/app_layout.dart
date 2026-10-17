import 'package:flutter/foundation.dart';

/// Native platforms keep their UI family when the available size changes.
enum AppLayout {
  desktop,
  mobile;

  static AppLayout get current => switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux =>
          desktop,
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia =>
          mobile,
      };
}
