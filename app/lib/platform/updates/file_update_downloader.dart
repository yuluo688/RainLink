import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../data/updates/github_release_source.dart';
import '../../domain/updates/app_update.dart';

class FileUpdateDownloader implements UpdatePackageDownloader {
  FileUpdateDownloader(
      {ReleaseOrigin? origin,
      Future<Directory> Function()? cacheDirectory,
      HttpClient Function()? createClient,
      this.timeout = const Duration(minutes: 10)})
      : origin = origin ?? ReleaseOrigin(),
        _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory,
        _createClient = createClient ?? HttpClient.new;
  final ReleaseOrigin origin;
  final Duration timeout;
  final Future<Directory> Function() _cacheDirectory;
  final HttpClient Function() _createClient;

  @override
  Future<DownloadedUpdate> download(
      AppRelease release, UpdateCancellation cancellation,
      {required void Function(int received, int total) onProgress}) async {
    final asset = release.asset;
    if (asset == null ||
        asset.sha256 == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(asset.sha256 ?? '') ||
        !origin.permitsAsset(asset.url, release.tag, asset.name) ||
        asset.bytes <= 0 ||
        asset.bytes > maximumUpdateBytes ||
        path.basename(asset.name) != asset.name) {
      throw const UpdateException('此更新包缺少可信校验信息，无法下载');
    }
    final client = _createClient()
      ..connectionTimeout = const Duration(seconds: 20);
    cancellation.bind(() => client.close(force: true));
    Directory? working;
    try {
      cancellation.check();
      final cache = await _cacheDirectory();
      final updates = await Directory(path.join(cache.path, 'updates'))
          .create(recursive: true);
      await _pruneDownloads(updates);
      working = await updates.createTemp('download-');
      final partial = File(path.join(working.path, '${asset.name}.partial'));
      final verified = File(path.join(working.path, asset.name));
      var timedOut = false;
      final timer = Timer(timeout, () {
        timedOut = true;
        client.close(force: true);
      });
      try {
        await _receive(client, asset, partial, cancellation, onProgress);
        if (timedOut) throw const UpdateException('下载更新超时，请重试');
      } on Exception {
        if (timedOut) throw const UpdateException('下载更新超时，请重试');
        rethrow;
      } finally {
        timer.cancel();
      }
      cancellation.check();
      final digest = await sha256.bind(partial.openRead()).first;
      cancellation.check();
      if (digest.toString() != asset.sha256) {
        throw const UpdateException('更新包校验失败，已丢弃下载');
      }
      await partial.rename(verified.path);
      cancellation.check();
      return DownloadedUpdate(release: release, path: verified.path);
    } on UpdateException {
      if (working != null) await _remove(working);
      rethrow;
    } on Exception {
      if (working != null) await _remove(working);
      cancellation.check();
      throw const UpdateException('无法下载或保存更新包，请检查网络与磁盘后重试');
    } finally {
      cancellation.bind(null);
      client.close(force: true);
    }
  }

  @override
  Future<void> discard(DownloadedUpdate update) async {
    final cache = await _cacheDirectory();
    final updates =
        path.normalize(path.absolute(path.join(cache.path, 'updates')));
    final working = Directory(path.dirname(path.absolute(update.path)));
    if (!path.equals(path.dirname(working.path), updates) ||
        !RegExp(r'^download-[A-Za-z0-9]+$')
            .hasMatch(path.basename(working.path)) ||
        await FileSystemEntity.type(working.path, followLinks: false) ==
            FileSystemEntityType.link) {
      throw const UpdateException('无法安全清理旧更新包');
    }
    await _remove(working);
  }

  Future<void> _pruneDownloads(Directory updates) async {
    final directories = <(Directory, DateTime)>[];
    await for (final entity in updates.list(followLinks: false)) {
      if (entity is Directory &&
          RegExp(r'^download-[A-Za-z0-9]+$')
              .hasMatch(path.basename(entity.path))) {
        directories.add((entity, (await entity.stat()).modified));
      }
    }
    directories.sort((a, b) => b.$2.compareTo(a.$2));
    for (var index = 0; index < directories.length; index++) {
      final (directory, modified) = directories[index];
      if (index >= 2 ||
          DateTime.now().difference(modified) > const Duration(days: 7)) {
        await _remove(directory);
      }
    }
  }

  Future<void> _remove(Directory working) async {
    try {
      if (await working.exists()) await working.delete(recursive: true);
    } on FileSystemException {
      throw const UpdateException('下载未完成，临时文件清理失败，请检查缓存目录权限后重试');
    }
  }

  Future<void> _receive(
      HttpClient client,
      ReleaseAsset asset,
      File output,
      UpdateCancellation cancellation,
      void Function(int, int) onProgress) async {
    var url = asset.url;
    HttpClientResponse? response;
    for (var redirects = 0; redirects <= 5; redirects++) {
      cancellation.check();
      final request = await client.getUrl(url);
      request.followRedirects = false;
      request.headers
          .set(HttpHeaders.userAgentHeader, 'RainLink-update-download');
      request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
      final current = await request.close();
      if ([301, 302, 303, 307, 308].contains(current.statusCode)) {
        final location = current.headers.value(HttpHeaders.locationHeader);
        final next = location == null ? null : Uri.tryParse(location);
        if (next == null || redirects == 5 || !origin.permitsRedirect(next)) {
          throw const UpdateException('更新包重定向不受信任，已停止下载');
        }
        final socket = await current.detachSocket();
        socket.destroy();
        url = next;
        continue;
      }
      response = current;
      break;
    }
    if (response == null || response.statusCode != HttpStatus.ok) {
      throw const UpdateException('更新包暂时不可用，请稍后重试');
    }
    if (response.contentLength > asset.bytes || response.contentLength == 0) {
      throw const UpdateException('更新包大小与发布信息不一致');
    }
    final sink = output.openWrite(mode: FileMode.writeOnly);
    var received = 0;
    try {
      await sink.addStream(response.map((chunk) {
        cancellation.check();
        received += chunk.length;
        if (received > asset.bytes) {
          throw const UpdateException('更新包超出发布大小，已停止下载');
        }
        onProgress(received, asset.bytes);
        return chunk;
      }));
      await sink.flush();
    } finally {
      await sink.close();
    }
    cancellation.check();
    if (received != asset.bytes) throw const UpdateException('更新包下载不完整，请重试');
  }
}
