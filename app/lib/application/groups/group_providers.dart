import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/groups/node_group.dart';
import '../../domain/groups/subscription_review.dart';
import '../../domain/nodes/proxy_node.dart';

final groupRepositoryProvider =
    Provider<GroupRepository>((ref) => const _UnavailableGroups());
final subscriptionFetcherProvider = Provider<SubscriptionFetcher>((ref) {
  throw StateError('SubscriptionFetcher must be provided during bootstrap.');
});
final groupsProvider = StreamProvider<List<NodeGroup>>(
    (ref) => ref.watch(groupRepositoryProvider).watchGroups());

/// null = all; empty = ungrouped; otherwise a persisted group ID.
final nodeGroupFilterProvider = StateProvider<String?>((ref) => null);
final subscriptionControllerProvider =
    StateNotifierProvider<SubscriptionController, Set<String>>(
        (ref) => SubscriptionController(ref.watch(groupRepositoryProvider)));
final subscriptionMaintenanceProvider =
    Provider<SubscriptionMaintenance?>((ref) => null);

class SubscriptionController extends StateNotifier<Set<String>> {
  SubscriptionController(this.repository) : super(const {});
  final GroupRepository repository;
  final Map<String, SubscriptionCancellation> _jobs = {};
  final _pending = <Future<void>>{};
  bool _suspended = false;
  bool isBusy(String id) => _jobs.containsKey(id);
  bool _disposed = false;

  Future<T> _run<T>(
      String id, Future<T> Function(SubscriptionCancellation) work,
      {SubscriptionCancellation? cancellation}) async {
    if (_jobs.containsKey(id)) throw const NodeException('此订阅正在更新');
    if (_disposed || _suspended) throw const SubscriptionCancelled();
    final token = cancellation ?? SubscriptionCancellation();
    _jobs[id] = token;
    state = {..._jobs.keys};
    Future<void>? settled;
    try {
      final operation = work(token);
      // The originating caller retains its error. This completion future only
      // lets safe exit await cancellation without reporting that error twice.
      settled =
          operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
      _pending.add(settled);
      return await operation;
    } finally {
      _pending.remove(settled);
      _jobs.remove(id);
      if (!_disposed) state = {..._jobs.keys};
    }
  }

  Future<String> importUrl(String url, SubscriptionCancellation token,
          {bool autoUpdate = true}) =>
      _run('@import',
          (t) => repository.importUrl(url, t, autoUpdate: autoUpdate),
          cancellation: token);
  Future<void> refresh(String id, {SubscriptionCancellation? cancellation}) =>
      _run(id, (t) => repository.refresh(id, t), cancellation: cancellation);
  Future<String> acceptReview(SubscriptionReview review,
          {SubscriptionCancellation? cancellation, bool autoUpdate = true}) =>
      _run(review.groupId ?? '@import', (token) {
        if (repository case final SubscriptionReviewRepository reviews) {
          return reviews.acceptReview(review, token, autoUpdate: autoUpdate);
        }
        throw const NodeException('当前订阅存储不支持兼容确认，请重新获取订阅');
      }, cancellation: cancellation);
  void cancel(String id) => _jobs[id]?.cancel();

  Future<void> suspend() async {
    _suspended = true;
    for (final token in _jobs.values) {
      token.cancel();
    }
    await Future.wait(_pending.toList());
  }

  void resume() => _suspended = false;
  @override
  void dispose() {
    _disposed = true;
    for (final token in _jobs.values) {
      token.cancel();
    }
    super.dispose();
  }
}

/// Checks due subscriptions while the application is active, with one bounded
/// operation at a time. Failed attempts retain old nodes and wait their interval.
class SubscriptionMaintenance {
  SubscriptionMaintenance(this.repository, this.controller,
      {DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final GroupRepository repository;
  final SubscriptionController controller;
  final DateTime Function() _now;
  Timer? _timer;
  bool _checking = false;
  bool _active = false;
  Future<void>? _pending;
  String? _updating;
  String? lastError;
  void resume() {
    if (_active) return;
    _active = true;
    _timer = Timer.periodic(
        const Duration(minutes: 1), (_) => unawaited(checkDue()));
    unawaited(checkDue());
  }

  void pause() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    if (_updating case final id?) controller.cancel(id);
  }

  Future<void> checkDue() async {
    final pending = _pending;
    if (pending != null) return pending;
    final operation = _checkDue();
    _pending = operation;
    try {
      await operation;
    } finally {
      _pending = null;
    }
  }

  Future<void> suspend() async {
    pause();
    await _pending;
  }

  Future<void> _checkDue() async {
    if (_checking || !_active) return;
    _checking = true;
    try {
      final groups = await repository.watchGroups().first;
      for (final group in groups) {
        if (!_active) break;
        if (!group.isDue(_now()) || controller.isBusy(group.id)) {
          continue;
        }
        try {
          _updating = group.id;
          await controller.refresh(group.id);
        } on NodeException catch (error) {
          lastError = error.message;
        } on Exception {
          lastError = '订阅自动更新失败，请到分组查看';
        } finally {
          _updating = null;
        }
      }
    } on Exception {
      lastError = '无法读取待更新的订阅';
    } finally {
      _checking = false;
    }
  }
}

class _UnavailableGroups implements GroupRepository {
  const _UnavailableGroups();
  Never _error() => throw const NodeException('分组存储尚未初始化');
  @override
  Stream<List<NodeGroup>> watchGroups() => Stream.value(const []);
  @override
  Future<String> importUrl(String url, SubscriptionCancellation cancellation,
          {bool autoUpdate = true}) async =>
      _error();
  @override
  Future<void> refresh(
          String id, SubscriptionCancellation cancellation) async =>
      _error();
  @override
  Future<String> createManual(String name) async => _error();
  @override
  Future<void> rename(NodeGroup group, String name) async => _error();
  @override
  Future<void> setAutoUpdate(NodeGroup group, bool enabled) async => _error();
  @override
  Future<void> select(String? groupId) async => _error();
  @override
  Future<void> moveUngrouped(String nodeId, String groupId) async => _error();
  @override
  Future<void> delete(String id) async => _error();
}
