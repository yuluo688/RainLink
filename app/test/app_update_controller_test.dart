import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/updates/app_update_controller.dart';
import 'package:rainlink/domain/updates/app_update.dart';

AppRelease _release([String tag = 'v0.2.0+1']) {
  final version = AppVersion.tryParse(tag);
  if (version == null) throw ArgumentError.value(tag);
  return AppRelease(
      tag: tag,
      version: version,
      notes: '测试更新',
      publishedAt: DateTime.utc(2026, 10, 17),
      preview: version.isPreview,
      page: Uri.https('github.com', '/yuluo688/RainLink/releases/tag/$tag'),
      asset: ReleaseAsset(
          name: 'RainLink-0.2.0+1-windows-x64.zip',
          url: Uri.https('github.com',
              '/yuluo688/RainLink/releases/download/$tag/RainLink-0.2.0+1-windows-x64.zip'),
          bytes: 100,
          sha256: '0' * 64));
}

class _Preferences implements UpdatePreferencesRepository {
  UpdatePreferences value = const UpdatePreferences();
  Exception? loadFailure;
  Exception? writeFailure;
  Completer<void>? writing;
  @override
  Future<UpdatePreferences> load() async {
    if (loadFailure case final failure?) throw failure;
    return value;
  }

  @override
  Future<void> save(UpdatePreferences preferences) async {
    await writing?.future;
    if (writeFailure case final failure?) throw failure;
    value = preferences;
  }
}

class _Source implements AppReleaseSource {
  AppRelease? release = _release();
  final calls = <bool>[];
  final tokens = <UpdateCancellation>[];
  Completer<AppRelease?>? pending;
  Exception? failure;
  @override
  Future<AppRelease?> latest(
      {required bool includePreview,
      required UpdateCancellation cancellation}) async {
    calls.add(includePreview);
    tokens.add(cancellation);
    if (failure case final value?) throw value;
    return pending?.future ?? release;
  }
}

class _Downloader implements UpdatePackageDownloader {
  int calls = 0;
  Completer<DownloadedUpdate>? pending;
  void Function(int, int)? progress;
  UpdateCancellation? token;
  final discarded = <DownloadedUpdate>[];
  @override
  Future<void> discard(DownloadedUpdate update) async => discarded.add(update);
  @override
  Future<DownloadedUpdate> download(
      AppRelease release, UpdateCancellation cancellation,
      {required void Function(int, int) onProgress}) async {
    calls++;
    token = cancellation;
    progress = onProgress;
    return pending?.future ??
        DownloadedUpdate(release: release, path: 'fixture/package.zip');
  }
}

class _Prepared implements PreparedUpdate {
  int commits = 0;
  int aborts = 0;
  Exception? abortFailure;
  @override
  Future<void> commit() async {
    commits++;
  }

  @override
  Future<void> abort() async {
    aborts++;
    if (abortFailure case final failure?) throw failure;
  }
}

class _Installer implements UpdateInstaller {
  int calls = 0;
  final prepared = _Prepared();
  Completer<PreparedUpdate>? pending;
  @override
  Future<PreparedUpdate> prepare(
      DownloadedUpdate update, UpdateCancellation cancellation) async {
    calls++;
    return pending?.future ?? prepared;
  }
}

class _Fixture {
  _Fixture({String version = '0.1.0+1'}) {
    controller = AppUpdateController(
        source: source,
        preferences: preferences,
        downloader: downloader,
        installer: installer,
        shutdown: shutdown,
        currentVersion: version);
  }
  final source = _Source();
  final preferences = _Preferences();
  final downloader = _Downloader();
  final installer = _Installer();
  final shutdown = UpdateShutdownCoordinator();
  late final AppUpdateController controller;
  Future<void> close() async {
    await controller.close();
    controller.dispose();
  }
}

void main() {
  test(
      'startup is opt-in and preferences preserve their confirmed state on failure',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.controller.start();
    expect(f.source.calls, isEmpty);
    f.preferences.writeFailure = Exception('private path');
    await f.controller
        .savePreferences(const UpdatePreferences(checkOnStartup: true));
    expect(f.controller.state.preferences.checkOnStartup, isFalse);
    expect(f.controller.state.error, isNot(contains('private')));
    f.preferences.writeFailure = null;
    await f.controller.savePreferences(
        const UpdatePreferences(checkOnStartup: true, includePreview: true));
    await f.controller.start();
    expect(f.source.calls, [true]);
    expect(f.downloader.calls, 0);
    expect(f.installer.calls, 0);
    expect(f.controller.state.phase, AppUpdatePhase.available);
  });

  test('failed preference load is retryable and no update request bypasses it',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    f.preferences.loadFailure = Exception('private');
    await f.controller.check();
    expect(f.source.calls, isEmpty);
    expect(f.controller.state.error, contains('无法读取'));
    f.preferences.loadFailure = null;
    await f.controller.check();
    expect(f.source.calls.length, 1);
    expect(f.controller.state.phase, AppUpdatePhase.available);
  });

  test('no releases, current versions and malformed local build are distinct',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    f.source.release = null;
    await f.controller.check();
    expect(f.controller.state.phase, AppUpdatePhase.empty);
    expect(f.controller.state.checkedAt, isNotNull);
    f.source.release = _release('v0.1.0+1');
    await f.controller.check();
    expect(f.controller.state.phase, AppUpdatePhase.current);
    await f.controller.download();
    expect(f.downloader.calls, 0);
    final invalid = _Fixture(version: 'not-a-build');
    addTearDown(invalid.close);
    await invalid.controller.check();
    expect(invalid.source.calls, isEmpty);
    expect(invalid.controller.state.error, contains('当前构建版本无效'));
  });

  test(
      'cancelling a metadata request ignores its late result and permits a new check',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.controller.initialize();
    final old = Completer<AppRelease?>();
    f.source.pending = old;
    final checking = f.controller.check();
    await Future<void>.delayed(Duration.zero);
    expect(f.controller.state.phase, AppUpdatePhase.checking);
    f.controller.cancel();
    expect(f.source.tokens.single.isCancelled, isTrue);
    f.source.pending = null;
    f.source.release = null;
    await f.controller.check();
    old.complete(_release());
    await checking;
    expect(f.controller.state.phase, AppUpdatePhase.empty);
    expect(f.controller.state.release, isNull);
  });

  test(
      'download cancellation ignores late progress and cannot produce install eligibility',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.controller.check();
    final pending = Completer<DownloadedUpdate>();
    f.downloader.pending = pending;
    final downloading = f.controller.download();
    f.downloader.progress?.call(50, 100);
    expect(f.controller.state.received, 50);
    f.controller.cancel();
    expect(f.downloader.token?.isCancelled, isTrue);
    f.downloader.progress?.call(100, 100);
    pending.complete(
        DownloadedUpdate(release: _release(), path: 'fixture/late.zip'));
    await downloading;
    expect(f.controller.state.phase, AppUpdatePhase.available);
    expect(f.controller.state.package, isNull);
    expect(f.downloader.discarded.single.path, 'fixture/late.zip');
    await f.controller.install();
    expect(f.installer.calls, 0);
  });

  test(
      'changing channel clears previous release/package only after preferences commit',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.controller.check();
    await f.controller.download();
    expect(f.controller.state.package, isNotNull);
    f.preferences.writeFailure = Exception('fixture write failure');
    await f.controller
        .savePreferences(const UpdatePreferences(includePreview: true));
    expect(f.controller.state.package, isNotNull);
    expect(f.controller.state.preferences.includePreview, isFalse);
    f.preferences.writeFailure = null;
    await f.controller
        .savePreferences(const UpdatePreferences(includePreview: true));
    expect(f.controller.state.phase, AppUpdatePhase.idle);
    expect(f.controller.state.package, isNull);
    expect(f.controller.state.release, isNull);
  });

  test('install preparation uses the shutdown coordinator before committing',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.controller.check();
    await f.controller.download();
    var requested = false;
    final detach = f.shutdown.attach((prepared) async {
      requested = true;
      expect(f.installer.prepared.commits, 0);
      expect(f.controller.state.phase, AppUpdatePhase.installing);
      await prepared.commit();
    });
    await f.controller.install();
    detach();
    expect(requested, isTrue);
    expect(f.installer.prepared.commits, 1);
    expect(f.installer.prepared.aborts, 0);
  });

  test(
      'shutdown refusal aborts prepared update and retains a usable downloaded package',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.controller.check();
    await f.controller.download();
    f.shutdown.attach((_) async => throw const UpdateException('网络尚未恢复'));
    await f.controller.install();
    expect(f.installer.prepared.aborts, 1);
    expect(f.installer.prepared.commits, 0);
    expect(f.controller.state.phase, AppUpdatePhase.downloaded);
    expect(f.controller.state.error, '网络尚未恢复');
    expect(f.controller.state.package, isNotNull);
  });

  test('cancelling preparation aborts a helper that becomes ready late',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.controller.check();
    await f.controller.download();
    final pending = Completer<PreparedUpdate>();
    f.installer.pending = pending;
    final installing = f.controller.install();
    f.controller.cancel();
    pending.complete(f.installer.prepared);
    await installing;
    expect(f.installer.prepared.aborts, 1);
    expect(f.installer.prepared.commits, 0);
    expect(f.controller.state.phase, AppUpdatePhase.downloaded);
  });

  test(
      'normal close cancels I/O and waits for transfers and pending preference writes',
      () async {
    final f = _Fixture();
    try {
      await f.controller.check();
      final pending = Completer<DownloadedUpdate>();
      f.downloader.pending = pending;
      final downloading = f.controller.download();
      var closed = false;
      final closing = f.controller.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(f.downloader.token?.isCancelled, isTrue);
      expect(closed, isFalse);
      pending.completeError(const UpdateCancelled());
      await downloading;
      await closing;
    } finally {
      f.controller.dispose();
    }
    final saving = _Fixture();
    try {
      await saving.controller.initialize();
      saving.preferences.writing = Completer<void>();
      final write = saving.controller
          .savePreferences(const UpdatePreferences(checkOnStartup: true));
      var closed = false;
      final closing = saving.controller.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      saving.preferences.writing?.complete();
      await write;
      await closing;
      expect(saving.preferences.value.checkOnStartup, isTrue);
      expect(saving.controller.state.preferences.checkOnStartup, isTrue);
    } finally {
      saving.controller.dispose();
    }
  });

  test(
      'refused exit resumes the controller without circular installation waits',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.controller.check();
    await f.controller.download();
    f.shutdown.attach((prepared) async {
      await f.controller.close(handingOff: true);
      f.controller.resumeAfterFailedExit();
      throw const UpdateException('fixture destroy failed');
    });
    await f.controller.install().timeout(const Duration(seconds: 1));
    expect(f.installer.prepared.aborts, 1);
    expect(f.controller.state.working, isFalse);
    expect(f.controller.state.phase, AppUpdatePhase.downloaded);
    expect(f.controller.state.package, isNotNull);
    await f.controller.check();
    expect(f.controller.state.phase, AppUpdatePhase.available);
  });
}
