import 'package:flutter/widgets.dart';

enum QrCameraStatus {
  idle,
  starting,
  scanning,
  paused,
  permissionDenied,
  unavailable,
  timedOut,
  failed;

  bool get hasFailure => switch (this) {
    permissionDenied || unavailable || timedOut || failed => true,
    _ => false,
  };

  String get message => switch (this) {
    idle || starting => '正在打开相机…',
    scanning => '将一个二维码放入取景区域',
    paused => '相机已暂停，返回应用后继续',
    permissionDenied => '未获得相机权限，可在系统设置中开启，或返回粘贴链接',
    unavailable => '当前设备无法使用相机，请返回粘贴链接',
    timedOut => '打开相机超时，请重试或返回粘贴链接',
    failed => '相机暂时不可用，请重试或返回粘贴链接',
  };
}

/// A platform view with one owned camera session; no import or storage logic.
abstract class QrCameraSession extends ValueNotifier<QrCameraStatus> {
  QrCameraSession() : super(QrCameraStatus.idle);
  Stream<List<String>> get codes;
  Widget buildPreview();
  Future<void> setActive(bool active);
  Future<void> retry();
  Future<void> close();
}

typedef QrCameraFactory = QrCameraSession Function();

class QrCameraException implements Exception {
  const QrCameraException();
  @override
  String toString() => '无法释放相机资源，请重试';
}
