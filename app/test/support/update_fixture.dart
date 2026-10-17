// Local test data only. Production never imports this file or contacts these URLs.
import 'dart:async';

import 'package:rainlink/application/updates/app_update_controller.dart';
import 'package:rainlink/domain/updates/app_update.dart';

AppRelease fixtureUpdateRelease({bool digest = true}) => AppRelease(
    tag: 'v0.2.0+1',
    version: AppVersion.tryParse('0.2.0+1') ??
        (throw StateError('Invalid fixture version')),
    notes: '改进连接稳定性与节点筛选。\n优化紧凑布局和深浅主题。',
    publishedAt: DateTime.utc(2026, 10, 17),
    preview: false,
    page: Uri.https('github.com', '/yuluo688/RainLink/releases/tag/v0.2.0+1'),
    asset: ReleaseAsset(
        name: 'RainLink-0.2.0+1-windows-x64.zip',
        url: Uri.https('github.com',
            '/yuluo688/RainLink/releases/download/v0.2.0+1/RainLink-0.2.0+1-windows-x64.zip'),
        bytes: 40 * 1024 * 1024,
        sha256: digest ? 'a' * 64 : null));

class FixtureUpdatePreferences implements UpdatePreferencesRepository {
  UpdatePreferences value = const UpdatePreferences();
  bool reject = false;
  @override
  Future<UpdatePreferences> load() async => value;
  @override
  Future<void> save(UpdatePreferences preferences) async {
    if (reject) throw Exception('fixture disk failure');
    value = preferences;
  }
}

class FixtureReleaseSource implements AppReleaseSource {
  AppRelease? release;
  Exception? failure;
  Completer<AppRelease?>? pending;
  int requests = 0;
  @override
  Future<AppRelease?> latest(
      {required bool includePreview,
      required UpdateCancellation cancellation}) async {
    requests++;
    if (failure case final error?) throw error;
    return pending?.future ?? release;
  }
}

class FixtureUpdateDownloader implements UpdatePackageDownloader {
  Completer<DownloadedUpdate>? pending;
  void Function(int, int)? progress;
  final discarded = <DownloadedUpdate>[];
  @override
  Future<DownloadedUpdate> download(
      AppRelease release, UpdateCancellation cancellation,
      {required void Function(int received, int total) onProgress}) async {
    progress = onProgress;
    return pending?.future ??
        DownloadedUpdate(release: release, path: 'fixture/update.zip');
  }

  @override
  Future<void> discard(DownloadedUpdate update) async => discarded.add(update);
}

class FixturePreparedUpdate implements PreparedUpdate {
  int commits = 0;
  int aborts = 0;
  @override
  Future<void> commit() async => commits++;
  @override
  Future<void> abort() async => aborts++;
}

class FixtureUpdateInstaller implements UpdateInstaller {
  final prepared = FixturePreparedUpdate();
  @override
  Future<PreparedUpdate> prepare(
          DownloadedUpdate update, UpdateCancellation cancellation) async =>
      prepared;
}

/// A layout fixture sets states directly; transport/behavior tests use the real
/// controller. These states never count as evidence of a third-party update.
class VisualUpdateController extends AppUpdateController {
  VisualUpdateController(AppUpdateState value)
      : super(
            source: null,
            preferences: null,
            downloader: null,
            installer: null,
            shutdown: UpdateShutdownCoordinator()) {
    state = value;
  }
}
