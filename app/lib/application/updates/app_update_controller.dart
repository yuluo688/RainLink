import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/build_info.g.dart';
import '../../domain/updates/app_update.dart';

final appReleaseSourceProvider = Provider<AppReleaseSource?>((ref) => null);
final updatePreferencesProvider = Provider<UpdatePreferencesRepository?>(
  (ref) => null,
);
final updateDownloaderProvider = Provider<UpdatePackageDownloader?>(
  (ref) => null,
);
final updateInstallerProvider = Provider<UpdateInstaller?>((ref) => null);

enum UpdateInstallationMode { desktopRestart, androidInstaller }

final updateInstallationModeProvider = Provider<UpdateInstallationMode>(
  (ref) => UpdateInstallationMode.desktopRestart,
);
final updateReceiptProvider = Provider<Future<String?> Function()?>(
  (ref) => null,
);
final startupReadyProvider = Provider<Future<void>>((ref) => Future.value());
final updateShutdownProvider = Provider((ref) => UpdateShutdownCoordinator());
final appUpdateControllerProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>(
      (ref) => AppUpdateController(
        source: ref.watch(appReleaseSourceProvider),
        preferences: ref.watch(updatePreferencesProvider),
        downloader: ref.watch(updateDownloaderProvider),
        installer: ref.watch(updateInstallerProvider),
        installationMode: ref.watch(updateInstallationModeProvider),
        receipt: ref.watch(updateReceiptProvider),
        shutdown: ref.watch(updateShutdownProvider),
      ),
    );

/// The window owns safe shutdown; the update page does not bypass it.
class UpdateShutdownCoordinator {
  Future<void> Function(PreparedUpdate)? _handler;
  void Function() attach(Future<void> Function(PreparedUpdate) handler) {
    _handler = handler;
    return () {
      if (_handler == handler) _handler = null;
    };
  }

  Future<void> request(PreparedUpdate update) {
    final handler = _handler;
    if (handler == null) throw const UpdateException('当前窗口不支持安装交接，请保持应用打开后重试');
    return handler(update);
  }
}

enum AppUpdatePhase {
  unavailable,
  idle,
  checking,
  empty,
  current,
  available,
  downloading,
  downloaded,
  preparing,
  installing,
  restartRequired,
  failed,
}

class AppUpdateState {
  const AppUpdateState({
    this.phase = AppUpdatePhase.idle,
    this.preferences = const UpdatePreferences(),
    this.loading = false,
    this.saving = false,
    this.error = '',
    this.notice = '',
    this.release,
    this.package,
    this.checkedAt,
    this.received = 0,
    this.total = 0,
  });
  final AppUpdatePhase phase;
  final UpdatePreferences preferences;
  final bool loading;
  final bool saving;
  final String error;
  final String notice;
  final AppRelease? release;
  final DownloadedUpdate? package;
  final DateTime? checkedAt;
  final int received;
  final int total;
  bool get awaitingRestart => phase == AppUpdatePhase.restartRequired;
  bool get working =>
      loading ||
      saving ||
      [
        AppUpdatePhase.checking,
        AppUpdatePhase.downloading,
        AppUpdatePhase.preparing,
        AppUpdatePhase.installing,
      ].contains(phase);
  AppUpdateState copyWith({
    AppUpdatePhase? phase,
    UpdatePreferences? preferences,
    bool? loading,
    bool? saving,
    String? error,
    String? notice,
    AppRelease? release,
    DownloadedUpdate? package,
    DateTime? checkedAt,
    int? received,
    int? total,
    bool clearRelease = false,
    bool clearPackage = false,
  }) => AppUpdateState(
    phase: phase ?? this.phase,
    preferences: preferences ?? this.preferences,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    error: error ?? this.error,
    notice: notice ?? this.notice,
    release: clearRelease ? null : release ?? this.release,
    package: clearPackage ? null : package ?? this.package,
    checkedAt: checkedAt ?? this.checkedAt,
    received: received ?? this.received,
    total: total ?? this.total,
  );
}

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController({
    required this.source,
    required this.preferences,
    required this.downloader,
    required this.installer,
    required this.shutdown,
    this.installationMode = UpdateInstallationMode.desktopRestart,
    this.receipt,
    String currentVersion = rainlinkVersion,
  }) : current = AppVersion.tryParse(currentVersion),
       super(
         AppUpdateState(
           phase:
               source == null
                   ? AppUpdatePhase.unavailable
                   : AppUpdatePhase.idle,
         ),
       );
  final AppReleaseSource? source;
  final UpdatePreferencesRepository? preferences;
  final UpdatePackageDownloader? downloader;
  final UpdateInstaller? installer;
  final UpdateShutdownCoordinator shutdown;
  final UpdateInstallationMode installationMode;
  final Future<String?> Function()? receipt;
  final AppVersion? current;
  Future<void>? _initializing;
  Future<void>? _saving;
  final _operations = <Future<void>>{};
  UpdateCancellation? _cancellation;
  bool _initialized = false;
  bool _closing = false;
  int _generation = 0;

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    if (_initialized || !mounted || _closing || source == null) return;
    state = state.copyWith(loading: true, error: '');
    try {
      final repository = preferences;
      if (repository == null) throw const UpdateException('当前构建未接入更新偏好存储');
      final value = await repository.load();
      final previousResult = await receipt?.call();
      if (!mounted || _closing) return;
      _initialized = true;
      state = state.copyWith(
        preferences: value,
        loading: false,
        notice: previousResult ?? '',
      );
    } on Exception {
      if (mounted && !_closing) {
        state = state.copyWith(loading: false, error: '无法读取更新偏好，请检查本地存储后重试');
      }
    } finally {
      if (!_initialized) _initializing = null;
    }
  }

  Future<void> start() async {
    await initialize();
    if (mounted &&
        !_closing &&
        _initialized &&
        state.preferences.checkOnStartup) {
      await check();
    }
  }

  Future<void> savePreferences(UpdatePreferences next) {
    if (!mounted ||
        _closing ||
        state.working ||
        state.awaitingRestart ||
        !_initialized) {
      return Future.value();
    }
    final operation = _savePreferences(next);
    _saving = operation;
    return operation;
  }

  Future<void> _savePreferences(UpdatePreferences next) async {
    state = state.copyWith(saving: true, error: '');
    try {
      final repository = preferences;
      if (repository == null) throw const UpdateException('当前构建未接入更新偏好存储');
      await repository.save(next);
      if (!mounted) return;
      final changed = next.includePreview != state.preferences.includePreview;
      final previousPackage = changed ? state.package : null;
      state = state.copyWith(
        preferences: next,
        saving: false,
        phase: changed ? AppUpdatePhase.idle : null,
        clearRelease: changed,
        clearPackage: changed,
      );
      await _discard(previousPackage);
    } on Exception {
      if (mounted) {
        state = state.copyWith(saving: false, error: '更新偏好未能保存，已保留原设置');
      }
    }
  }

  Future<void> check() => _track(_check);
  Future<void> _check() async {
    await initialize();
    if (!mounted ||
        _closing ||
        !_initialized ||
        state.working ||
        state.awaitingRestart ||
        source == null) {
      return;
    }
    if (current == null) {
      state = state.copyWith(error: '当前构建版本无效，无法比较更新');
      return;
    }
    final token = _begin(AppUpdatePhase.checking);
    final generation = _generation;
    try {
      final release = await source?.latest(
        includePreview: state.preferences.includePreview,
        cancellation: token,
      );
      if (!_current(generation, token)) return;
      final previousPackage = state.package;
      state = state.copyWith(
        phase:
            release == null
                ? AppUpdatePhase.empty
                : release.version.compareTo(current ?? release.version) > 0
                ? AppUpdatePhase.available
                : AppUpdatePhase.current,
        release: release,
        clearRelease: release == null,
        clearPackage: true,
        checkedAt: DateTime.now(),
      );
      await _discard(previousPackage);
    } on UpdateCancelled {
      if (_current(generation, token)) {
        state = state.copyWith(phase: _settledPhase());
      }
    } on Exception catch (error) {
      if (_current(generation, token)) {
        state = state.copyWith(
          phase: AppUpdatePhase.failed,
          error: _message(error, '检查更新失败，请重试'),
        );
      }
    } finally {
      if (identical(_cancellation, token)) _cancellation = null;
    }
  }

  Future<void> download() => _track(_download);
  Future<void> _download() async {
    final release = state.release;
    final service = downloader;
    if (!mounted ||
        _closing ||
        state.working ||
        state.awaitingRestart ||
        release == null ||
        service == null ||
        current == null ||
        release.version.compareTo(current ?? release.version) <= 0) {
      return;
    }
    final token = _begin(AppUpdatePhase.downloading);
    final generation = _generation;
    var previousPercent = -1;
    try {
      final package = await service.download(
        release,
        token,
        onProgress: (received, total) {
          if (!_current(generation, token)) return;
          final percent = total > 0 ? received * 100 ~/ total : 0;
          if (percent == previousPercent) return;
          previousPercent = percent;
          state = state.copyWith(received: received, total: total);
        },
      );
      if (!_current(generation, token)) {
        await _discard(package);
        return;
      }
      state = state.copyWith(
        phase: AppUpdatePhase.downloaded,
        package: package,
      );
    } on UpdateCancelled {
      if (_current(generation, token)) {
        state = state.copyWith(phase: _settledPhase());
      }
    } on Exception catch (error) {
      if (_current(generation, token)) {
        state = state.copyWith(
          phase: AppUpdatePhase.failed,
          error: _message(error, '下载更新失败，请重试'),
        );
      }
    } finally {
      if (identical(_cancellation, token)) _cancellation = null;
    }
  }

  Future<void> _discard(DownloadedUpdate? package) async {
    if (package == null) return;
    try {
      await downloader?.discard(package);
    } on Exception {
      if (mounted && !_closing) {
        state = state.copyWith(error: '旧更新包未能清理，请检查缓存目录权限');
      }
    }
  }

  Future<void> install() => _track(_install);
  Future<void> _install() async {
    final package = state.package;
    final service = installer;
    if (!mounted ||
        _closing ||
        state.working ||
        package == null ||
        service == null) {
      return;
    }
    final token = _begin(AppUpdatePhase.preparing);
    final generation = _generation;
    PreparedUpdate? prepared;
    try {
      prepared = await service.prepare(package, token);
      if (!_current(generation, token)) {
        await prepared.abort();
        return;
      }
      state = state.copyWith(phase: AppUpdatePhase.installing);
      await shutdown.request(prepared);
      if (installationMode == UpdateInstallationMode.androidInstaller &&
          _current(generation, token)) {
        state = state.copyWith(
          phase: AppUpdatePhase.restartRequired,
          clearPackage: true,
        );
        await _discard(package);
      }
    } on Exception catch (error) {
      String? cleanupError;
      try {
        await prepared?.abort();
      } on Exception {
        cleanupError = '安装交接失败，准备文件未能完全清理；请保持应用打开后重试';
      }
      if (_current(generation, token)) {
        state = state.copyWith(
          phase: AppUpdatePhase.downloaded,
          error: cleanupError ?? _message(error, '安装交接失败，应用保持打开，请重试'),
        );
      }
    } finally {
      if (identical(_cancellation, token)) _cancellation = null;
    }
  }

  String _message(Exception error, String fallback) =>
      error is UpdateException ? error.message : fallback;
  UpdateCancellation _begin(AppUpdatePhase phase) {
    _cancellation?.cancel();
    final token = UpdateCancellation();
    _cancellation = token;
    ++_generation;
    state = state.copyWith(phase: phase, error: '', received: 0, total: 0);
    return token;
  }

  bool _current(int generation, UpdateCancellation token) =>
      mounted &&
      !_closing &&
      generation == _generation &&
      identical(_cancellation, token) &&
      !token.isCancelled;
  AppUpdatePhase _settledPhase() {
    if (state.package != null) return AppUpdatePhase.downloaded;
    final release = state.release;
    if (release == null) {
      return state.checkedAt == null
          ? AppUpdatePhase.idle
          : AppUpdatePhase.empty;
    }
    return release.version.compareTo(current ?? release.version) > 0
        ? AppUpdatePhase.available
        : AppUpdatePhase.current;
  }

  void cancel() {
    if (!mounted ||
        _closing ||
        state.awaitingRestart ||
        state.phase == AppUpdatePhase.installing) {
      return;
    }
    ++_generation;
    _cancellation?.cancel();
    _cancellation = null;
    state = state.copyWith(phase: _settledPhase(), error: '');
  }

  Future<void> _track(Future<void> Function() action) {
    late final Future<void> operation;
    operation = action().whenComplete(() => _operations.remove(operation));
    _operations.add(operation);
    return operation;
  }

  Future<void> close({bool handingOff = false}) async {
    if (!mounted) return;
    _closing = true;
    ++_generation;
    if (!handingOff) _cancellation?.cancel();
    await _initializing;
    await _saving;
    // Installation itself requests shutdown; do not await that circular future.
    if (!handingOff) {
      await Future.wait(_operations.toList());
    }
  }

  /// A refused window/network exit must not leave update controls locked.
  void resumeAfterFailedExit({String? message}) {
    if (!mounted) return;
    _closing = false;
    _cancellation = null;
    if (!_initialized) _initializing = null;
    state = state.copyWith(
      phase: _settledPhase(),
      loading: false,
      saving: false,
      error: message ?? '安装交接未完成，应用保持打开，可重试',
    );
  }

  @override
  void dispose() {
    _closing = true;
    ++_generation;
    _cancellation?.cancel();
    super.dispose();
  }
}
