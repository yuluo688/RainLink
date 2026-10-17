import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/chains/proxy_chain.dart';
import '../../domain/identity/record_id.dart';
import '../../domain/nodes/proxy_node.dart';

final chainRepositoryProvider =
    Provider<ChainRepository>((ref) => const _UnavailableChains());
final chainTesterProvider =
    Provider<ChainTester>((ref) => const UnavailableChainTester());
final chainsProvider = StreamProvider<List<ProxyChain>>(
    (ref) => ref.watch(chainRepositoryProvider).watch());
final selectedChainIdProvider = StreamProvider<String?>(
    (ref) => ref.watch(chainRepositoryProvider).watchSelectedId());
final selectedChainProvider = Provider<ProxyChain?>((ref) {
  final id = ref.watch(selectedChainIdProvider).valueOrNull;
  return ref
      .watch(chainsProvider)
      .valueOrNull
      ?.where((chain) => chain.id == id)
      .firstOrNull;
});

class ChainEditorState {
  ChainEditorState(
      {required this.draft,
      this.test,
      this.testing = false,
      this.saving = false,
      this.dirty = false,
      this.error = '',
      this.notice = ''});
  final ProxyChain draft;
  final ChainTestResult? test;
  final bool testing;
  final bool saving;
  final bool dirty;
  final String error;
  final String notice;
  bool get busy => testing || saving;
}

final chainEditorProvider =
    StateNotifierProvider.autoDispose<ChainEditorController, ChainEditorState>(
        (ref) {
  final controller = ChainEditorController(
      ref.watch(chainRepositoryProvider), ref.watch(chainTesterProvider));
  void hydrate(List<ProxyChain>? chains) {
    final selection = ref.read(selectedChainIdProvider);
    if (controller.initial && chains != null && selection.hasValue) {
      final id = selection.valueOrNull;
      final chain = chains.where((chain) => chain.id == id).firstOrNull ??
          chains.firstOrNull;
      if (chain != null) controller.load(chain);
    }
  }

  hydrate(ref.read(chainsProvider).valueOrNull);
  ref.listen(chainsProvider, (_, next) => hydrate(next.valueOrNull));
  ref.listen(selectedChainIdProvider,
      (_, next) => hydrate(ref.read(chainsProvider).valueOrNull));
  return controller;
});

class ChainEditorController extends StateNotifier<ChainEditorState> {
  ChainEditorController(this.repository, this.tester)
      : super(ChainEditorState(
            draft: ProxyChain(id: newRecordId(), name: '新代理链', hopIds: [])));
  final ChainRepository repository;
  final ChainTester tester;
  int _generation = 0;
  bool initial = true;

  void load(ProxyChain? chain) {
    if (state.busy) return;
    initial = false;
    state = ChainEditorState(
        draft: chain ?? ProxyChain(id: newRecordId(), name: '新代理链', hopIds: []),
        test: chain?.lastTest);
  }

  void rename(String name) => _edit(state.draft.copyWith(name: name));
  void setHops(List<String> ids) => _edit(state.draft.copyWith(hopIds: ids));
  void _edit(ProxyChain draft) {
    if (state.busy) return;
    initial = false;
    state = ChainEditorState(draft: draft, test: state.test, dirty: true);
  }

  ChainSnapshot snapshot(List<ProxyNode> nodes) {
    final byId = {for (final node in nodes) node.id: node};
    final hops = <ProxyNode>[];
    for (final id in state.draft.hopIds) {
      final node = byId[id];
      if (node == null) throw const ChainException('部分节点已删除，请更换跳点');
      hops.add(node);
    }
    final result = ChainSnapshot(state.draft, hops);
    result.validate();
    return result;
  }

  Future<void> test(List<ProxyNode> nodes) async {
    if (state.busy) return;
    final generation = ++_generation;
    try {
      final frozen = snapshot(nodes);
      state = ChainEditorState(
          draft: state.draft, dirty: state.dirty, testing: true);
      final result = await tester.testChain(frozen);
      if (!mounted || generation != _generation) return;
      state = ChainEditorState(
          draft: state.draft,
          dirty: state.dirty,
          test: result,
          notice: result.passed ? '整条路径测试通过' : '',
          error:
              result.passed ? '' : result.hops.lastOrNull?.error ?? '链路测试未通过');
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        state = ChainEditorState(
            draft: state.draft, dirty: state.dirty, error: error.toString());
      }
    }
  }

  Future<void> cancel() async {
    if (!state.testing) return;
    final generation = ++_generation;
    try {
      await tester.cancelChainTest();
      if (mounted && generation == _generation) {
        state = ChainEditorState(
            draft: state.draft, dirty: state.dirty, notice: '测试已取消');
      }
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        state = ChainEditorState(
            draft: state.draft, dirty: state.dirty, error: error.toString());
      }
    }
  }

  Future<bool> save(List<ProxyNode> nodes) async {
    if (state.busy) return false;
    try {
      final frozen = snapshot(nodes);
      final test = state.test;
      state = ChainEditorState(
          draft: state.draft, dirty: state.dirty, test: test, saving: true);
      final saved = await repository.save(frozen, test: test);
      if (mounted) {
        state = ChainEditorState(
            draft: saved, test: saved.lastTest, notice: '已保存并选中，请到概览连接');
      }
      return true;
    } on Exception catch (error) {
      if (mounted) {
        state = ChainEditorState(
            draft: state.draft,
            dirty: state.dirty,
            test: state.test,
            error: error.toString());
      }
      return false;
    }
  }

  Future<void> delete() async {
    if (state.busy || state.draft.revision == 0) return;
    state = ChainEditorState(
        draft: state.draft, dirty: state.dirty, test: state.test, saving: true);
    try {
      await repository.delete(state.draft);
      if (mounted) {
        state = ChainEditorState(
            draft: ProxyChain(id: newRecordId(), name: '新代理链', hopIds: []));
      }
    } on Exception catch (error) {
      if (mounted) {
        state = ChainEditorState(
            draft: state.draft,
            dirty: state.dirty,
            test: state.test,
            error: error.toString());
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    if (state.testing) unawaited(tester.cancelChainTest());
    super.dispose();
  }
}

class UnavailableChainTester implements ChainTester {
  const UnavailableChainTester();
  @override
  Future<void> validateChain(ChainSnapshot chain) async =>
      throw const ChainException('当前平台的代理链核心尚未接入');
  @override
  Future<ChainTestResult> testChain(ChainSnapshot chain) async =>
      throw const ChainException('当前平台的链路测试尚未接入');
  @override
  Future<void> cancelChainTest() async {}
}

class _UnavailableChains implements ChainRepository {
  const _UnavailableChains();
  @override
  Stream<List<ProxyChain>> watch() => Stream.value(const []);
  @override
  Stream<String?> watchSelectedId() => Stream.value(null);
  @override
  Future<ProxyChain> save(ChainSnapshot draft, {ChainTestResult? test}) async =>
      throw const ChainException('代理链存储尚未初始化');
  @override
  Future<void> select(ProxyChain chain) async =>
      throw const ChainException('代理链存储尚未初始化');
  @override
  Future<void> delete(ProxyChain chain) async =>
      throw const ChainException('代理链存储尚未初始化');
}
