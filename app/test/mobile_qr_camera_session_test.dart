import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:rainlink/platform/qr/mobile_qr_camera_session.dart';
import 'package:rainlink/platform/qr/qr_camera_session.dart';

const _attributes = MobileScannerViewAttributes(
  cameraDirection: CameraFacing.back,
  currentTorchMode: TorchState.off,
  size: Size(640, 480),
  numberOfCameras: 1,
);

class _Platform extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  final events = <String>[];
  final options = <StartOptions>[];
  Completer<MobileScannerViewAttributes>? gate;
  Exception? startFailure;
  bool failStop = false;
  bool failDispose = false;
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    events.add('start');
    options.add(startOptions);
    if (startFailure case final failure?) throw failure;
    return gate == null ? _attributes : await gate!.future;
  }

  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<void> stop() async {
    events.add('stop');
    if (failStop) throw PlatformException(code: 'private-fixture');
  }

  @override
  Future<void> dispose() async {
    events.add('dispose');
    if (failDispose) throw PlatformException(code: 'private-fixture');
  }
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'camera starts on demand, scans only QR and owns pause/resume/close',
    () async {
      final platform = _Platform();
      final camera = MobileQrCameraSession(platform: platform);
      expect(platform.events, isEmpty);
      final captured = <List<String>>[];
      final subscription = camera.codes.listen(captured.add);
      await camera.setActive(true);
      expect(camera.value, QrCameraStatus.scanning);
      expect(platform.options.single.formats, [BarcodeFormat.qrCode]);
      expect(platform.options.single.returnImage, isFalse);
      platform.captures.add(
        const BarcodeCapture(barcodes: [Barcode(rawValue: 'fixture')]),
      );
      await _tick();
      expect(captured, [
        ['fixture'],
      ]);
      await camera.setActive(false);
      expect(camera.value, QrCameraStatus.paused);
      platform.captures.add(
        const BarcodeCapture(barcodes: [Barcode(rawValue: 'late')]),
      );
      await _tick();
      expect(captured, hasLength(1));
      await camera.setActive(true);
      expect(camera.value, QrCameraStatus.scanning);
      await camera.close();
      await camera.close();
      expect(platform.events, ['start', 'stop', 'start', 'stop', 'dispose']);
      expect(platform.captures.hasListener, isFalse);
      await subscription.cancel();
      await platform.captures.close();
    },
  );

  for (final (error, status) in [
    (MobileScannerErrorCode.permissionDenied, QrCameraStatus.permissionDenied),
    (MobileScannerErrorCode.unsupported, QrCameraStatus.unavailable),
    (MobileScannerErrorCode.genericError, QrCameraStatus.failed),
  ]) {
    test('native $error is safe, does not auto-loop and can retry', () async {
      final platform =
          _Platform()
            ..startFailure = MobileScannerException(
              errorCode: error,
              errorDetails: const MobileScannerErrorDetails(
                message: 'private-fixture',
              ),
            );
      final camera = MobileQrCameraSession(platform: platform);
      await camera.setActive(true);
      expect(camera.value, status);
      expect(camera.value.message, isNot(contains('private-fixture')));
      await camera.setActive(false);
      await camera.setActive(true);
      expect(platform.options, hasLength(1));
      platform.startFailure = null;
      await camera.retry();
      expect(camera.value, QrCameraStatus.scanning);
      expect(platform.options, hasLength(2));
      await camera.close();
      expect(platform.captures.hasListener, isFalse);
      await platform.captures.close();
    });
  }

  test(
    'permission response after timeout/exit is stopped before next scanner',
    () async {
      final firstPlatform =
          _Platform()..gate = Completer<MobileScannerViewAttributes>();
      final first = MobileQrCameraSession(
        platform: firstPlatform,
        startTimeout: const Duration(milliseconds: 10),
      );
      final starting = first.setActive(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(first.value, QrCameraStatus.timedOut);
      final closing = first.close();
      final secondPlatform = _Platform();
      final second = MobileQrCameraSession(platform: secondPlatform);
      final secondStarting = second.setActive(true);
      await _tick();
      expect(secondPlatform.events, isEmpty);
      firstPlatform.gate!.complete(_attributes);
      await starting;
      await closing;
      await secondStarting;
      expect(firstPlatform.events, ['start', 'stop', 'dispose']);
      expect(second.value, QrCameraStatus.scanning);
      await second.close();
      await firstPlatform.captures.close();
      await secondPlatform.captures.close();
    },
  );

  test(
    'permission lifecycle events coalesce without concurrent starts',
    () async {
      final platform =
          _Platform()..gate = Completer<MobileScannerViewAttributes>();
      final camera = MobileQrCameraSession(platform: platform);
      final start = camera.setActive(true);
      await _tick();
      final paused = camera.setActive(false);
      final resumed = camera.setActive(true);
      platform.gate!.complete(_attributes);
      await Future.wait([start, paused, resumed]);
      expect(platform.events, ['start']);
      expect(camera.value, QrCameraStatus.scanning);
      await camera.close();
      await platform.captures.close();
    },
  );

  test(
    'native decoding failure stops the stream and never exposes payload',
    () async {
      final platform = _Platform();
      final camera = MobileQrCameraSession(platform: platform);
      await camera.setActive(true);
      platform.captures.addError(PlatformException(code: 'private-fixture'));
      await _tick();
      expect(camera.value, QrCameraStatus.failed);
      expect(platform.events, ['start', 'stop']);
      expect(camera.value.message, isNot(contains('private-fixture')));
      await camera.close();
      await platform.captures.close();
    },
  );

  test(
    'failed stop still disposes, removes listeners and reports safe failure',
    () async {
      final platform = _Platform();
      final camera = MobileQrCameraSession(platform: platform);
      await camera.setActive(true);
      platform.failStop = true;
      await expectLater(camera.close(), throwsA(isA<QrCameraException>()));
      expect(platform.events, ['start', 'stop', 'dispose']);
      expect(platform.captures.hasListener, isFalse);
      await platform.captures.close();
      // The lease is released even when resource disposal reports a failure.
      final nextPlatform = _Platform();
      final next = MobileQrCameraSession(platform: nextPlatform);
      await next.setActive(true);
      await next.close();
      await nextPlatform.captures.close();
    },
  );
}
