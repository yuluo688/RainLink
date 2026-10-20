import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'qr_camera_session.dart';

/// Owns the native view and subscriptions. Camera operations are serial,
/// including late permission responses and another scanner being opened.
class MobileQrCameraSession extends QrCameraSession {
  MobileQrCameraSession({
    MobileScannerPlatform? platform,
    this.startTimeout = const Duration(seconds: 30),
  }) : _platform = platform ?? MobileScannerPlatform.instance {
    _previousLease = _lastLease;
    _lastLease = _leaseReleased.future;
    _subscription = _platform.barcodesStream.listen(
      (capture) {
        if (capture != null &&
            _active &&
            !_closing &&
            !_failed &&
            value == QrCameraStatus.scanning) {
          _codes.add([
            for (final barcode in capture.barcodes)
              if (barcode.rawValue case final text?) text,
          ]);
        }
      },
      onError: (Object error, StackTrace stack) {
        // Native decoder errors can contain the payload. Forward a fixed state
        // only, then stop the failed camera through the normal serial path.
        if (!_closing) {
          _failed = true;
          value = QrCameraStatus.failed;
          unawaited(setActive(false));
        }
      },
    );
  }

  static Future<void> _lastLease = Future<void>.value();
  final _leaseReleased = Completer<void>();
  late final Future<void> _previousLease;
  final MobileScannerPlatform _platform;
  final Duration startTimeout;
  final _codes = StreamController<List<String>>.broadcast();
  late final StreamSubscription<BarcodeCapture?> _subscription;
  Future<void> _pending = Future<void>.value();
  Future<void>? _closeFuture;
  Size _previewSize = const Size(640, 480);
  bool _active = false;
  bool _closing = false;
  bool _failed = false;
  bool _running = false;
  bool _needsStop = false;

  @override
  Stream<List<String>> get codes => _codes.stream;

  @override
  Widget buildPreview() =>
      !_running
          ? const ColoredBox(color: Colors.black)
          : ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox.fromSize(
                size: _previewSize,
                child: _platform.buildCameraView(),
              ),
            ),
          );

  @override
  Future<void> setActive(bool active) {
    if (_closing) return _pending;
    _active = active;
    _pending = _pending.then((_) => _synchronize());
    return _pending;
  }

  @override
  Future<void> retry() {
    if (_closing) return _pending;
    _pending = _pending.then((_) async {
      if (_closing) return;
      try {
        await _stop();
        _failed = false;
        _active = true;
        await _synchronize();
      } on Exception {
        _failed = true;
        value = QrCameraStatus.failed;
      }
    });
    return _pending;
  }

  Future<void> _stop() async {
    if (!_needsStop) return;
    await _platform.stop();
    _needsStop = false;
    _running = false;
  }

  Future<void> _synchronize() async {
    await _previousLease;
    if (_closing) return;
    if (!_active) {
      try {
        await _stop();
        if (!_failed) value = QrCameraStatus.paused;
      } on Exception {
        _failed = true;
        value = QrCameraStatus.failed;
      }
      return;
    }
    if (_failed || _running) return;
    value = QrCameraStatus.starting;
    final watchdog = Timer(startTimeout, () {
      if (!_closing) {
        _failed = true;
        _active = false;
        value = QrCameraStatus.timedOut;
      }
    });
    try {
      // Do not abandon this Future on timeout: an OS permission response is
      // uncancellable and its eventual camera must be released before reuse.
      await _stop();
      _needsStop = true;
      final attributes = await _platform.start(
        const StartOptions(
          cameraDirection: CameraFacing.back,
          cameraResolution: null,
          detectionSpeed: DetectionSpeed.normal,
          detectionTimeoutMs: 400,
          formats: [BarcodeFormat.qrCode],
          returnImage: false,
          torchEnabled: false,
          invertImage: false,
          autoZoom: false,
        ),
      );
      _running = true;
      if (attributes.size.width > 0 && attributes.size.height > 0) {
        _previewSize = attributes.size;
      }
      if (!_closing && _active && !_failed) value = QrCameraStatus.scanning;
      if (_closing || !_active || _failed) await _stop();
    } on MobileScannerException catch (error) {
      _failed = true;
      if (!_closing) {
        value = switch (error.errorCode) {
          MobileScannerErrorCode.permissionDenied =>
            QrCameraStatus.permissionDenied,
          MobileScannerErrorCode.unsupported => QrCameraStatus.unavailable,
          _ => QrCameraStatus.failed,
        };
      }
    } on Exception {
      _failed = true;
      if (!_closing) value = QrCameraStatus.failed;
    } finally {
      watchdog.cancel();
    }
  }

  @override
  Future<void> close() {
    if (_closeFuture case final closing?) return closing;
    _closing = true;
    _active = false;
    return _closeFuture = _close();
  }

  Future<void> _close() async {
    var failed = false;
    await _subscription.cancel();
    await _pending;
    await _previousLease;
    try {
      await _stop();
    } on Exception {
      failed = true;
    }
    try {
      // Dispose is also required after permission/start failure, and after a
      // failed stop. It must never run while another session owns the plugin.
      await _platform.dispose();
    } on Exception {
      failed = true;
    } finally {
      await _codes.close();
      super.dispose();
      _leaseReleased.complete();
    }
    if (failed) throw const QrCameraException();
  }
}
