import 'dart:convert';
import 'dart:io';

import 'package:rainlink/data/subscriptions/http_subscription_fetcher.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/groups/subscription_issue.dart';

/// Private input from tools/verify_subscription_path.py; never persist raw data.
Future<void> main() async {
  final report = <String, Object?>{'productionFetcher': true};
  try {
    final input = await stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    final config = jsonDecode(input) as Map<String, Object?>;
    final port = config['proxyPort']! as int;
    final source = Uri.parse(config['url']! as String);
    final document = await HttpSubscriptionFetcher(localProxyPort: () => port)
        .fetch(source, SubscriptionCancellation());
    final protocols = <String, int>{};
    for (final node in document.nodes) {
      protocols.update(node.protocol.wireName, (count) => count + 1,
          ifAbsent: () => 1);
    }
    report.addAll({
      'fetchedAndParsed': true,
      'compatibleNodes': document.nodes.length,
      'protocols': protocols,
      'skippedItems': document.skippedNodes,
      'issueCount': document.issues.length,
      'requiresReview': document.requiresReview,
      'usageProvided': document.uploaded != null && document.downloaded != null,
      'totalProvided': document.total != null,
      'expiryProvided': document.expiresAt != null,
      'databaseWritten': false,
    });
  } on SubscriptionContentException catch (error) {
    report.addAll({
      'fetchedAndParsed': false,
      'compatibleNodes': 0,
      'skippedItems': error.skippedNodes,
      'issueCount': error.issues.length,
    });
  } on Object catch (error) {
    // Runtime and transport exceptions can embed the full source URL.
    report.addAll(
        {'fetchedAndParsed': false, 'errorType': error.runtimeType.toString()});
  }
  stdout.writeln(jsonEncode(report));
  exitCode = report['fetchedAndParsed'] == true ? 0 : 1;
}
