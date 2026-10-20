import '../nodes/proxy_node.dart';

/// A preview only. Importing or connecting always requires another user action.
sealed class QrImport {
  const QrImport();
}

final class QrSubscription extends QrImport {
  const QrSubscription(this.url);
  final Uri url;
}

final class QrNode extends QrImport {
  const QrNode(this.draft);
  final NodeDraft draft;
}

/// An unauthenticated HTTP URL with a port can represent either kind of input.
final class QrHttpChoice extends QrImport {
  const QrHttpChoice({required this.subscription, required this.node});
  final QrSubscription subscription;
  final QrNode node;
}

abstract interface class QrImportParser {
  QrImport parse(String value);
}

class QrImportException implements Exception {
  const QrImportException(this.message);
  final String message;
  @override
  String toString() => message;
}
