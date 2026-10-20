import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/data/import/qr_import_parser.dart';
import 'package:rainlink/data/subscriptions/subscription_parser.dart';
import 'package:rainlink/domain/import/qr_import.dart';

import 'support/qr_fixtures.dart';

void main() {
  const parser = StandardQrImportParser();
  for (final entry in qrNodeLinks.entries) {
    test(
      'QR imports ${entry.key.label} using the complete existing grammar',
      () {
        final draft = (parser.parse(entry.value) as QrNode).draft;
        final expected = parseNodeUri(entry.value);
        expect(draft.protocol, entry.key);
        expect(draft.name, expected.name);
        expect(draft.server, expected.server);
        expect(draft.port, expected.port);
        expect(draft.tls, expected.tls);
        expect(draft.username, expected.username);
        expect(draft.password, expected.password);
        expect(draft.obfsPassword, expected.obfsPassword);
        expect(draft.options.toJson(), expected.options.toJson());
        expect(draft.original, isNull);
      },
    );
  }
  test('subscription paths, query tokens and Unicode remain preview data', () {
    for (final text in [
      'https://provider.example.test/api/sub?token=private-fixture',
      'http://provider.example.test:8080/sub',
      'https://provider.example.test',
      'https://provider.example.test/sub/中文',
    ]) {
      final result = parser.parse('  $text\n') as QrSubscription;
      expect(result.url, Uri.parse(text));
    }
  });
  test('bare HTTP port requires an explicit choice in either current tab', () {
    for (final text in [
      'http://proxy.example.test:8080',
      'https://proxy.example.test:8443/',
      'http://proxy.example.test:80',
      'https://proxy.example.test:443/',
    ]) {
      final result = parser.parse(text) as QrHttpChoice;
      expect(result.subscription.url, Uri.parse(text));
      expect(result.node.draft.server, 'proxy.example.test');
      expect(result.node.draft.tls, text.startsWith('https'));
    }
  });
  test('authenticated HTTP cannot silently become a subscription', () {
    expect(parser.parse('http://u:p@proxy.example.test:8080'), isA<QrNode>());
    expect(
      () =>
          parser.parse('http://u:private-fixture@proxy.example.test:8080/sub'),
      throwsA(
        isA<QrImportException>().having(
          (e) => e.message,
          'safe message',
          isNot(contains('private-fixture')),
        ),
      ),
    );
  });
  test('HTTP default scheme ports work for authenticated node links', () {
    for (final (scheme, port) in [('http', 80), ('https', 443)]) {
      for (final suffix in ['', ':$port']) {
        final node =
            parser.parse('$scheme://u:p@proxy.example.test$suffix') as QrNode;
        expect(node.draft.port, port);
        expect(node.draft.password, 'p');
      }
    }
  });
  test(
    'invalid, multiple, unsupported and oversized inputs are safe errors',
    () {
      for (final text in [
        '',
        'https://provider.example.test/sub\nhttps://other.example.test',
        'not-a-link-private-fixture',
        'file:///private-fixture',
        'javascript://private-fixture',
        'https://',
        'https://provider.example.test/\u0000private-fixture',
        'vmess://private-fixture',
        'hy2://private-fixture@example.test?obfs=bad',
        'https://provider.example.test:${'9' * 30}/sub',
        'ss://${'a' * 65536}',
      ]) {
        expect(
          () => parser.parse(text),
          throwsA(
            isA<QrImportException>().having(
              (e) => e.toString(),
              'safe diagnostic',
              isNot(contains('private-fixture')),
            ),
          ),
          reason: 'Invalid fixture',
        );
      }
    },
  );
  test('scheme case is normalized before encoded node parsing', () {
    final link = qrNodeLinks.values.last;
    expect(
      parser.parse(link.replaceFirst('tuic://', 'TUIC://')),
      isA<QrNode>(),
    );
    expect(
      parser.parse(
        qrNodeLinks.values.first.replaceFirst('https://', 'HTTPS://'),
      ),
      isA<QrNode>(),
    );
  });
}
