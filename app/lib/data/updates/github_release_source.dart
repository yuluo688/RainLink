import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/updates/app_update.dart';

const maximumUpdateBytes = 300 * 1024 * 1024;

/// Production origins are fixed. Loopback origins allow real isolated HTTP
/// integration tests without weakening the production HTTPS/redirect policy.
class ReleaseOrigin {
  ReleaseOrigin()
      : api = Uri.https('api.github.com', '/repos/yuluo688/RainLink/releases'),
        web = Uri.https('github.com', '/yuluo688/RainLink/releases');
  ReleaseOrigin.loopback(Uri base)
      : api = base.resolve('/repos/yuluo688/RainLink/releases'),
        web = base.resolve('/yuluo688/RainLink/releases') {
    if (base.scheme != 'http' ||
        !['127.0.0.1', '[::1]', 'localhost'].contains(base.host)) {
      throw ArgumentError('Loopback HTTP origin required');
    }
  }
  final Uri api;
  final Uri web;
  Uri get releasesEndpoint => api.replace(queryParameters: {'per_page': '100'});
  Uri page(String tag) =>
      web.replace(pathSegments: [...web.pathSegments, 'tag', tag]);
  Uri asset(String tag, String name) =>
      web.replace(pathSegments: [...web.pathSegments, 'download', tag, name]);
  bool permitsAsset(Uri uri, String tag, String name) =>
      uri == asset(tag, name);
  bool permitsRedirect(Uri uri) =>
      (uri.scheme == 'https' &&
          uri.host == 'release-assets.githubusercontent.com' &&
          (!uri.hasPort || uri.port == 443) &&
          uri.userInfo.isEmpty &&
          uri.fragment.isEmpty) ||
      (api.scheme == 'http' &&
          uri.origin == api.origin &&
          uri.userInfo.isEmpty &&
          uri.fragment.isEmpty);
}

class GithubReleaseSource implements AppReleaseSource {
  GithubReleaseSource(
      {ReleaseOrigin? origin,
      this.target = 'windows-x64',
      this.timeout = const Duration(seconds: 20),
      HttpClient Function()? createClient})
      : origin = origin ?? ReleaseOrigin(),
        _createClient = createClient ?? HttpClient.new;
  final ReleaseOrigin origin;
  final String target;
  final Duration timeout;
  final HttpClient Function() _createClient;
  static const _maximumBodyBytes = 4 * 1024 * 1024;

  @override
  Future<AppRelease?> latest(
      {required bool includePreview,
      required UpdateCancellation cancellation}) async {
    final client = _createClient()..connectionTimeout = timeout;
    cancellation.bind(() => client.close(force: true));
    try {
      return await _latest(client, includePreview, cancellation)
          .timeout(timeout, onTimeout: () {
        client.close(force: true);
        throw const UpdateException('检查更新超时，请检查网络后重试');
      });
    } on UpdateException {
      rethrow;
    } on Exception {
      cancellation.check();
      throw const UpdateException('无法检查更新，请检查网络与证书后重试');
    } finally {
      cancellation.bind(null);
      client.close(force: true);
    }
  }

  Future<AppRelease?> _latest(
      HttpClient client, bool preview, UpdateCancellation cancellation) async {
    cancellation.check();
    final request = await client.getUrl(origin.releasesEndpoint);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.userAgentHeader, 'RainLink-update-check');
    request.headers
        .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers.set('X-GitHub-Api-Version', '2022-11-28');
    final response = await request.close();
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const UpdateException('更新源限制了请求，请稍后再试');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw const UpdateException('更新源暂时不可用，请稍后重试');
    }
    if (response.contentLength > _maximumBodyBytes) {
      throw const UpdateException('更新信息过大，已停止读取');
    }
    final data = <int>[];
    await for (final chunk in response) {
      cancellation.check();
      if (data.length + chunk.length > _maximumBodyBytes) {
        throw const UpdateException('更新信息过大，已停止读取');
      }
      data.addAll(chunk);
    }
    cancellation.check();
    final Object? value;
    try {
      value = jsonDecode(utf8.decode(data));
    } on FormatException {
      throw const UpdateException('更新信息格式无效，请稍后重试');
    }
    if (value is! List<Object?> || value.length > 100) {
      throw const UpdateException('更新信息格式无效，请稍后重试');
    }
    AppRelease? best;
    for (final item in value) {
      if (item is! Map<String, Object?>) {
        throw const UpdateException('版本信息格式无效');
      }
      if (item['draft'] == true) continue;
      final tag = item['tag_name'];
      if (tag is! String) throw const UpdateException('版本信息缺少版本号');
      final version = AppVersion.tryParse(tag);
      // Unrelated tags cannot be compared or offered as application updates.
      if (version == null) continue;
      if (item['draft'] is! bool || item['prerelease'] is! bool) {
        throw const UpdateException('版本发布状态无效');
      }
      final isPreview = item['prerelease'] == true || version.isPreview;
      if (isPreview && !preview) continue;
      final page = Uri.tryParse(
          item['html_url'] is String ? item['html_url'] as String : '');
      final published = item['published_at'];
      final at = published is String ? DateTime.tryParse(published) : null;
      final notes = item['body'];
      if (page != origin.page(tag) ||
          at == null ||
          (notes != null && notes is! String) ||
          (notes is String && notes.length > 50000)) {
        throw const UpdateException('版本详情格式无效');
      }
      final assets = item['assets'];
      if (assets is! List<Object?> || assets.length > 100) {
        throw const UpdateException('更新包信息格式无效');
      }
      final expectedName =
          'RainLink-${tag.startsWith('v') ? tag.substring(1) : tag}-$target.zip';
      ReleaseAsset? asset;
      for (final value in assets) {
        if (value is! Map<String, Object?>) {
          throw const UpdateException('更新包信息格式无效');
        }
        if (value['name'] != expectedName) continue;
        final bytes = value['size'];
        final rawUrl = value['browser_download_url'];
        final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
        final digest = value['digest'];
        if (asset != null ||
            bytes is! int ||
            bytes <= 0 ||
            bytes > maximumUpdateBytes ||
            url == null ||
            !origin.permitsAsset(url, tag, expectedName) ||
            (digest != null &&
                (digest is! String ||
                    !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)))) {
          throw const UpdateException('更新包地址、大小或校验信息无效');
        }
        asset = ReleaseAsset(
            name: expectedName,
            url: url,
            bytes: bytes,
            sha256:
                digest is String ? digest.substring(7).toLowerCase() : null);
      }
      final release = AppRelease(
          tag: tag,
          version: version,
          notes: (notes as String? ?? '')
              .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ''),
          publishedAt: at.toUtc(),
          preview: isPreview,
          page: page ?? origin.page(tag),
          asset: asset);
      if (best == null || version.compareTo(best.version) > 0) best = release;
    }
    return best;
  }
}
