import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerRainlinkLicenses() {
  for (final (package, asset) in [
    ('Inter', 'assets/fonts/Inter-OFL.txt'),
    ('Noto Sans SC', 'assets/fonts/NotoSansSC-OFL.txt'),
    ('Roboto Mono', 'assets/fonts/RobotoMono-OFL.txt'),
    ('sing-box', 'assets/licenses/sing-box-LICENSE.txt'),
    ('Wintun 0.14.1', 'assets/licenses/wintun-LICENSE.txt'),
    ('go-winio', 'assets/licenses/go-winio-LICENSE.txt'),
  ]) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(
          [package], await rootBundle.loadString(asset));
    });
  }
}
