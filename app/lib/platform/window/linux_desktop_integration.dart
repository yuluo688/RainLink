import 'native_desktop_integration.dart';

class LinuxDesktopIntegration extends NativeDesktopIntegration {
  LinuxDesktopIntegration()
    : super(platformName: 'Linux', requireCapabilities: true);
}
