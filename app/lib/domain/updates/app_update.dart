class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateCancelled extends UpdateException {
  const UpdateCancelled() : super('更新操作已取消');
}

/// Cancelling closes owned network/process resources; late results cannot win.
class UpdateCancellation {
  bool _cancelled = false;
  void Function()? _abort;
  bool get isCancelled => _cancelled;
  void bind(void Function()? abort) {
    _abort = abort;
    if (_cancelled) abort?.call();
  }

  void cancel() {
    _cancelled = true;
    _abort?.call();
  }

  void check() {
    if (_cancelled) throw const UpdateCancelled();
  }
}

/// RainLink release tags follow pubspec versions, with an optional leading v.
/// Build numbers distinguish two shipped builds of the same semantic version.
class AppVersion implements Comparable<AppVersion> {
  AppVersion._(this.major, this.minor, this.patch, this.pre, this.build);
  final int major;
  final int minor;
  final int patch;
  final List<String> pre;
  final int build;
  bool get isPreview => pre.isNotEmpty;

  static AppVersion? tryParse(String text) {
    if (text.length > 128) return null;
    final match = RegExp(
            r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+(0|[1-9]\d*))?$')
        .firstMatch(text);
    if (match == null || match.end != text.length) return null;
    final parts = [
      for (final i in [1, 2, 3, 5]) int.tryParse(match.group(i) ?? '0')
    ];
    if (parts.any((v) => v == null || v > 0x7fffffff)) return null;
    final pre = match.group(4)?.split('.') ?? <String>[];
    if (pre.any((v) =>
        RegExp(r'^\d+$').hasMatch(v) && v.length > 1 && v.startsWith('0'))) {
      return null;
    }
    return AppVersion._(parts[0] ?? 0, parts[1] ?? 0, parts[2] ?? 0,
        List.unmodifiable(pre), parts[3] ?? 0);
  }

  @override
  int compareTo(AppVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch)
    ]) {
      final order = pair.$1.compareTo(pair.$2);
      if (order != 0) return order;
    }
    if (pre.isEmpty != other.pre.isEmpty) return pre.isEmpty ? 1 : -1;
    for (var i = 0; i < pre.length && i < other.pre.length; i++) {
      final a = pre[i], b = other.pre[i];
      final numericA = RegExp(r'^\d+$').hasMatch(a);
      final numericB = RegExp(r'^\d+$').hasMatch(b);
      final int order;
      if (numericA && numericB) {
        order = a.length != b.length
            ? a.length.compareTo(b.length)
            : a.compareTo(b);
      } else if (numericA != numericB) {
        order = numericA ? -1 : 1;
      } else {
        order = a.compareTo(b);
      }
      if (order != 0) return order;
    }
    final preOrder = pre.length.compareTo(other.pre.length);
    return preOrder != 0 ? preOrder : build.compareTo(other.build);
  }
}

class UpdatePreferences {
  const UpdatePreferences(
      {this.checkOnStartup = false, this.includePreview = false});
  final bool checkOnStartup;
  final bool includePreview;
  UpdatePreferences copyWith({bool? checkOnStartup, bool? includePreview}) =>
      UpdatePreferences(
          checkOnStartup: checkOnStartup ?? this.checkOnStartup,
          includePreview: includePreview ?? this.includePreview);
  Map<String, Object?> toJson() =>
      {'checkOnStartup': checkOnStartup, 'includePreview': includePreview};
  factory UpdatePreferences.fromJson(Map<String, Object?> value) {
    if (value
        case {'checkOnStartup': bool startup, 'includePreview': bool preview}) {
      return UpdatePreferences(
          checkOnStartup: startup, includePreview: preview);
    }
    throw const UpdateException('更新偏好格式无效');
  }
}

class ReleaseAsset {
  const ReleaseAsset(
      {required this.name,
      required this.url,
      required this.bytes,
      required this.sha256});
  final String name;
  final Uri url;
  final int bytes;
  final String? sha256;
}

class AppRelease {
  const AppRelease(
      {required this.tag,
      required this.version,
      required this.notes,
      required this.publishedAt,
      required this.preview,
      required this.page,
      this.asset});
  final String tag;
  final AppVersion version;
  final String notes;
  final DateTime publishedAt;
  final bool preview;
  final Uri page;
  final ReleaseAsset? asset;
}

abstract interface class AppReleaseSource {
  Future<AppRelease?> latest(
      {required bool includePreview, required UpdateCancellation cancellation});
}

abstract interface class UpdatePreferencesRepository {
  Future<UpdatePreferences> load();
  Future<void> save(UpdatePreferences preferences);
}

class DownloadedUpdate {
  const DownloadedUpdate({required this.release, required this.path});
  final AppRelease release;
  final String path;
}

abstract interface class UpdatePackageDownloader {
  Future<DownloadedUpdate> download(
      AppRelease release, UpdateCancellation cancellation,
      {required void Function(int received, int total) onProgress});
  Future<void> discard(DownloadedUpdate update);
}

abstract interface class PreparedUpdate {
  /// Hand off only after the app has restored network state and flushed data.
  Future<void> commit();
  Future<void> abort();
}

abstract interface class UpdateInstaller {
  Future<PreparedUpdate> prepare(
      DownloadedUpdate update, UpdateCancellation cancellation);
}
