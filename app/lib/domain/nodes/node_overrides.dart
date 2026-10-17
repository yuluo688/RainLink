/// Device-local choices never replace subscription-owned connection parameters.
abstract interface class NodeOverridesRepository {
  Future<void> setFavorite(String nodeId, bool favorite);
  Future<void> setAlias(String nodeId, String alias);
  Future<void> setHidden(String nodeId, bool hidden);
}
