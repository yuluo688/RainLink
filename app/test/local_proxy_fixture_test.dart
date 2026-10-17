import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/local_proxy_fixture.dart';

void main() {
  for (final halfClose in [false, true]) {
    test(
        'CONNECT fixture preserves fragmented tunnels (half-close: $halfClose)',
        () async {
      final hits = <String>[];
      final sockets = <Socket>{};
      final first = await LocalProxyFixture.start('A', hits, sockets);
      final second = await LocalProxyFixture.start('B', hits, sockets);
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final body = List<int>.generate(2 * 1024 * 1024, (index) => index % 251);
      final serving = origin.listen((request) async {
        request.response.contentLength = body.length;
        request.response.add(body);
        await request.response.close();
      });
      final readers = <StreamIterator<List<int>>>[];
      try {
        Future<(Socket, StreamIterator<List<int>>)> open(int target) async {
          final socket = await Socket.connect('127.0.0.1', first.server.port);
          sockets.add(socket);
          final reader = StreamIterator(socket);
          readers.add(reader);
          socket.write('CONNECT 127.0.0.1:$target HTTP/1.1\r\n\r\n');
          await socket.flush();
          var header = '';
          while (!header.endsWith('\r\n\r\n') && await reader.moveNext()) {
            header += latin1.decode(reader.current);
          }
          expect(header, 'HTTP/1.1 200 Connection Established\r\n\r\n');
          return (socket, reader);
        }

        final (socket, reader) = await open(second.server.port);
        socket.write('CONNECT 127.0.0.1:${origin.port} HTTP/1.1\r\n\r\n');
        await socket.flush();
        var header = '';
        while (!header.endsWith('\r\n\r\n') && await reader.moveNext()) {
          header += latin1.decode(reader.current);
        }
        expect(header, 'HTTP/1.1 200 Connection Established\r\n\r\n');
        // A separate background tunnel must not change the first tunnel's target.
        await open(origin.port);
        for (final fragment in [
          'GET / HTTP/1.1\r\nHost: localhost\r\nX-Rain',
          'Link-QA: marked-request\r',
          '\nConnection: close\r\n\r\n',
        ]) {
          socket.write(fragment);
          await socket.flush();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        if (halfClose) await socket.close();
        final bytes = <int>[];
        while (await reader.moveNext().timeout(const Duration(seconds: 5))) {
          bytes.addAll(reader.current);
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        final response = latin1.decode(bytes);
        final offset = response.indexOf('\r\n\r\n') + 4;
        expect(offset, greaterThan(3));
        expect(bytes.sublist(offset), body,
            reason: 'Normal upstream EOF must preserve the entire response');
        expect(first.requestPaths, {
          'marked-request': ['A>127.0.0.1:${second.server.port}']
        });
        expect(second.requestPaths, {
          'marked-request': ['B>127.0.0.1:${origin.port}']
        });
        expect([...first.failures, ...second.failures], isEmpty);
      } finally {
        for (final reader in readers) {
          await reader.cancel();
        }
        for (final socket in sockets) {
          socket.destroy();
        }
        await first.server.close();
        await second.server.close();
        await origin.close(force: true);
        await serving.cancel();
      }
    });
  }
}
