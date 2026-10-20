import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import '../../domain/updates/app_update.dart';

/// Android owns APK identity/signature checks and the system consent screens.
/// A staged copy stays private until a narrowly scoped content URI is granted.
class AndroidUpdateInstaller implements UpdateInstaller {
  AndroidUpdateInstaller({
    MethodChannel? channel,
    this.prepareTimeout = const Duration(seconds: 45),
    this.controlTimeout = const Duration(seconds: 5),
  }) : _channel = channel ?? const MethodChannel('rainlink/updates');

  final MethodChannel _channel;
  final Duration prepareTimeout;
  final Duration controlTimeout;

  @override
  Future<PreparedUpdate> prepare(
    DownloadedUpdate update,
    UpdateCancellation cancellation,
  ) async {
    cancellation.check();
    final release = update.release;
    final asset = release.asset;
    final versionName =
        release.tag.replaceFirst(RegExp(r'^v'), '').split('+').first;
    if (asset == null ||
        asset.name !=
            'RainLink-$versionName+${release.version.build}-android-universal.apk' ||
        asset.sha256 == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(asset.sha256 ?? '') ||
        release.version.build < 1) {
      throw const UpdateException('Android 更新包的版本或校验信息无效');
    }
    final random = Random.secure();
    final id =
        List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    Future<void> cancel() async {
      try {
        await _invokeControl<void>(_channel, 'cancelPrepare', controlTimeout, {
          'id': id,
        });
      } on PlatformException {
        throw const UpdateException('安装准备取消未完成，请保持应用打开后重试');
      }
    }

    // Cancellation is observed by the original future as well, so a late
    // prepared result is never handed to a newer installation attempt.
    Future<void>? cancelling;
    void requestCancel() {
      cancelling ??= cancel();
      unawaited(cancelling?.catchError((Object _, StackTrace __) {}));
    }

    cancellation.bind(requestCancel);
    try {
      final token = await _channel
          .invokeMethod<String>('prepare', {
            'id': id,
            'path': update.path,
            'bytes': asset.bytes,
            'sha256': asset.sha256,
            'versionName': versionName,
            'versionCode': release.version.build,
          })
          .timeout(
            prepareTimeout,
            onTimeout: () {
              requestCancel();
              throw const UpdateException('安装包校验超时，请重试');
            },
          );
      if (token != id) throw const UpdateException('系统返回了无效的安装准备结果');
      if (cancellation.isCancelled) {
        await _invokeControl<void>(_channel, 'abort', controlTimeout, {
          'id': id,
        });
        throw const UpdateCancelled();
      }
      return _AndroidPreparedUpdate(_channel, id, controlTimeout);
    } on PlatformException catch (error) {
      cancellation.check();
      throw _safeError(error);
    } on MissingPluginException {
      throw const UpdateException('当前构建未接入 Android 安装服务');
    } finally {
      cancellation.bind(null);
      await cancelling;
    }
  }

  Future<String?> readReceipt() async {
    try {
      final status = await _invokeControl<String>(
        _channel,
        'receipt',
        controlTimeout,
      );
      return switch (status) {
        null => null,
        'installed' => '上次更新已安装，当前运行新版本',
        'interrupted' => '上次安装未完成，原版本仍可使用，请重新检查更新',
        _ => throw const UpdateException('无法确认上次安装结果'),
      };
    } on PlatformException catch (error) {
      throw _safeError(error);
    }
  }
}

class _AndroidPreparedUpdate implements PreparedUpdate {
  _AndroidPreparedUpdate(this.channel, this.id, this.controlTimeout);
  final MethodChannel channel;
  final String id;
  final Duration controlTimeout;
  bool _finished = false;

  @override
  Future<void> commit() async {
    if (_finished) throw const UpdateException('安装准备已结束，请重新下载或重试');
    try {
      await channel.invokeMethod<void>('commit', {'id': id});
      _finished = true;
    } on PlatformException catch (error) {
      throw _safeError(error);
    }
  }

  @override
  Future<void> abort() async {
    if (_finished) return;
    try {
      await _invokeControl<void>(channel, 'abort', controlTimeout, {'id': id});
      _finished = true;
    } on PlatformException catch (error) {
      throw _safeError(error);
    }
  }
}

// System consent has no artificial deadline. Only short, noninteractive control
// requests are bounded, including the cancellation ACK after a prepare timeout.
Future<T?> _invokeControl<T>(
  MethodChannel channel,
  String method,
  Duration timeout, [
  Map<String, Object?>? arguments,
]) => channel
    .invokeMethod<T>(method, arguments)
    .timeout(
      timeout,
      onTimeout: () => throw const UpdateException('安装服务响应超时，请保持应用打开后重试'),
    );

UpdateException _safeError(PlatformException error) => switch (error.code) {
  'cancelled' => const UpdateCancelled(),
  'permission_denied' => const UpdateException('未允许 RainLink 安装应用，原版本保持可用'),
  'invalid_package' => const UpdateException('安装包的身份、版本或签名校验失败，已停止安装'),
  'busy' => const UpdateException('请先完成当前安装或系统授权'),
  'cleanup_failed' => const UpdateException('安装临时文件未能清理，请保持应用打开后重试'),
  _ => const UpdateException('系统安装未完成，原版本保持可用，请重试'),
};
