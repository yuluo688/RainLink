import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/import/qr_import_providers.dart';
import '../../../design_system/theme/rainlink_colors.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../domain/import/qr_import.dart';
import '../../../platform/qr/qr_camera_session.dart';

final qrCameraFactoryProvider = Provider<QrCameraFactory?>((ref) => null);

Future<QrImport?> showQrImportDialog(BuildContext context) =>
    showDialog<QrImport>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const QrImportDialog(),
    );

class QrImportDialog extends ConsumerStatefulWidget {
  const QrImportDialog({super.key});
  @override
  ConsumerState<QrImportDialog> createState() => _QrImportDialogState();
}

class _QrImportDialogState extends ConsumerState<QrImportDialog>
    with WidgetsBindingObserver {
  QrCameraSession? _camera;
  StreamSubscription<List<String>>? _subscription;
  Future<void>? _releaseFuture;
  String? _error;
  String? _lastInvalid;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera = ref.read(qrCameraFactoryProvider)?.call();
    _subscription = _camera?.codes.listen(
      _capture,
      onError: (Object error, StackTrace stack) {
        if (mounted) setState(() => _error = '识别暂时失败，请重试或返回粘贴链接');
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final state = WidgetsBinding.instance.lifecycleState;
        unawaited(
          _camera?.setActive(
            state == null || state == AppLifecycleState.resumed,
          ),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_finishing) {
      unawaited(_camera?.setActive(state == AppLifecycleState.resumed));
    }
  }

  void _capture(List<String> values) {
    if (_finishing || !mounted) return;
    final codes = values.where((v) => v.trim().isNotEmpty).toSet();
    if (codes.isEmpty) return;
    if (codes.length != 1) {
      setState(() => _error = '检测到多个二维码，请只保留一个');
      return;
    }
    final text = codes.single;
    if (text == _lastInvalid) return;
    try {
      final result = ref.read(qrImportParserProvider).parse(text);
      unawaited(_finish(result));
    } on QrImportException catch (error) {
      _lastInvalid = text;
      setState(() => _error = error.message);
    }
  }

  Future<void> _release() =>
      _releaseFuture ??= () async {
        await _subscription?.cancel();
        await _camera?.close();
      }();

  void _reportReleaseFailure(Object error, StackTrace stack) {
    // Only the fixed, non-sensitive diagnostic is sent to Flutter's handler.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: const QrCameraException(),
        stack: stack,
        library: 'RainLink QR camera',
      ),
    );
  }

  Future<void> _finish(QrImport? result) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    if (result == null) {
      // Closing the UI must not wait for an unanswered OS permission prompt.
      // The platform adapter still observes and releases that late result.
      unawaited(_release().catchError(_reportReleaseFailure));
      if (mounted) Navigator.of(context).pop();
      return;
    }
    try {
      await _release().timeout(const Duration(seconds: 5));
      if (mounted) Navigator.of(context).pop(result);
    } on Exception {
      if (mounted) {
        setState(() {
          _finishing = false;
          _error = '相机关闭未完成，请返回后重试';
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_release().catchError(_reportReleaseFailure));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    final camera = _camera;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_finish(null));
      },
      child: Dialog(
        insetPadding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.viewPaddingOf(context).top + 16,
          16,
          16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const ValueKey('qr-back'),
                      tooltip: '返回添加',
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(44),
                      ),
                      onPressed: () => _finish(null),
                      icon: const RainlinkIcon(RainlinkGlyph.back, size: 18),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '扫码导入',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (camera != null)
                          ValueListenableBuilder<QrCameraStatus>(
                            valueListenable: camera,
                            builder:
                                (context, status, _) => Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final side = math.min(
                                          constraints.maxWidth,
                                          280.0,
                                        );
                                        return Center(
                                          child: SizedBox.square(
                                            dimension: side,
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  camera.buildPreview(),
                                                  if (status !=
                                                      QrCameraStatus.scanning)
                                                    ColoredBox(
                                                      color: colors.raised,
                                                      child: Center(
                                                        child:
                                                            status.hasFailure
                                                                ? RainlinkIcon(
                                                                  RainlinkGlyph
                                                                      .qr,
                                                                  size: 40,
                                                                  color:
                                                                      colors
                                                                          .muted,
                                                                )
                                                                : status ==
                                                                    QrCameraStatus
                                                                        .paused
                                                                ? RainlinkIcon(
                                                                  RainlinkGlyph
                                                                      .qr,
                                                                  size: 40,
                                                                  color:
                                                                      colors
                                                                          .muted,
                                                                )
                                                                : const SizedBox.square(
                                                                  dimension: 24,
                                                                  child: CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                                ),
                                                      ),
                                                    ),
                                                  IgnorePointer(
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            24,
                                                          ),
                                                      child: DecoratedBox(
                                                        decoration: BoxDecoration(
                                                          border: Border.all(
                                                            color:
                                                                colors.primary,
                                                            width: 1.5,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      status.message,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: colors.secondary),
                                    ),
                                    if (status.hasFailure &&
                                        status !=
                                            QrCameraStatus.unavailable) ...[
                                      const SizedBox(height: 8),
                                      TextButton(
                                        key: const ValueKey('qr-retry'),
                                        onPressed:
                                            _finishing ? null : camera.retry,
                                        child: const Text('重新尝试'),
                                      ),
                                    ],
                                  ],
                                ),
                          )
                        else
                          const Text('当前平台不支持相机扫码，请返回粘贴链接'),
                        if (_error case final error?) ...[
                          const SizedBox(height: 12),
                          Text(
                            error,
                            key: const ValueKey('qr-error'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.error),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          '支持订阅地址与节点分享链接，识别后确认导入。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const ValueKey('qr-return-paste'),
                    onPressed: () => _finish(null),
                    icon: const RainlinkIcon(RainlinkGlyph.copy, size: 16),
                    label: const Text('返回粘贴链接'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<QrImport?> resolveQrHttpChoice(
  BuildContext context,
  QrHttpChoice choice,
) => showDialog<QrImport>(
  context: context,
  builder:
      (context) => AlertDialog(
        title: const Text('选择链接用途'),
        content: const Text('这个 HTTP 地址同时可以表示订阅和单个代理节点，请选择用途。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, choice.node),
            child: const Text('HTTP 节点'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, choice.subscription),
            child: const Text('订阅地址'),
          ),
        ],
      ),
);
