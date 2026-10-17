import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Local-only CONNECT fixture shared by desktop and Android end-to-end tests.
class LocalProxyFixture {
  LocalProxyFixture(this.name, this.server, this.hits, this.sockets);
  final String name;
  final ServerSocket server;
  final List<String> hits;
  final Set<Socket> sockets;
  final accepted = <String>[];
  final failures = <String>[];
  final Map<String, List<String>> requestPaths = {};
  static Future<LocalProxyFixture> start(
      String name, List<String> hits, Set<Socket> sockets) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = LocalProxyFixture(name, server, hits, sockets);
    server.listen(fixture.handle);
    return fixture;
  }

  void handle(Socket local) {
    sockets.add(local);
    Socket? remote;
    var buffered = <int>[];
    var forwardedHeader = '';
    var traced = false;
    var destination = '';
    var closed = false;
    late StreamSubscription<List<int>> input;
    void forward(List<int> bytes) {
      if (!traced) {
        forwardedHeader += latin1.decode(bytes);
        final marker =
            RegExp(r'\r\nx-rainlink-qa: ([a-z0-9-]+)\r\n', caseSensitive: false)
                .firstMatch(forwardedHeader);
        final token = marker?.group(1);
        if (token != null) {
          requestPaths.putIfAbsent(token, () => []).add(destination);
          traced = true;
          forwardedHeader = '';
        } else if (forwardedHeader.length > 8192) {
          // Only inspect the beginning of this fixture's local HTTP stream.
          traced = true;
          forwardedHeader = '';
        }
      }
      remote!.add(bytes);
    }

    void close() {
      closed = true;
      local.destroy();
      remote?.destroy();
    }

    Future<void> finish(Socket? output) async {
      if (closed) return;
      if (output == null) {
        close();
        return;
      }
      try {
        // A normal EOF closes only this direction after queued writes drain.
        // destroy() here can truncate a response or discard a half-close reply.
        await output.close().timeout(const Duration(seconds: 5));
      } on IOException catch (error) {
        if (!closed) failures.add('$name: $error');
        close();
      } on TimeoutException {
        if (!closed) failures.add('$name: timed out draining tunnel');
        close();
      }
    }

    input = local.listen((bytes) async {
      if (remote != null) {
        forward(bytes);
        return;
      }
      buffered.addAll(bytes);
      if (buffered.length > 8192) {
        close();
        return;
      }
      final header = latin1.decode(buffered);
      final end = header.indexOf('\r\n\r\n');
      if (end < 0) return;
      final line = header.substring(0, header.indexOf('\r\n')).split(' ');
      if (line.length < 3 || line.first != 'CONNECT') {
        close();
        return;
      }
      final target = Uri.parse('http://${line[1]}');
      // Keep fixtures local, including the core's optional public probes.
      if (target.host != '127.0.0.1') {
        close();
        return;
      }
      destination = '$name>${line[1]}';
      accepted.add(destination);
      input.pause();
      try {
        final upstream = await Socket.connect(target.host, target.port,
            timeout: const Duration(seconds: 2));
        remote = upstream;
        sockets.add(upstream);
        if (closed) {
          upstream.destroy();
          return;
        }
        hits.add('$name>${line[1]}');
        upstream.listen(local.add,
            onError: (Object _) => close(),
            onDone: () => unawaited(finish(local)));
        local.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        await local.flush();
        if (buffered.length > end + 4) forward(buffered.sublist(end + 4));
        buffered = [];
        input.resume();
      } on IOException catch (error) {
        failures.add('$name>${line[1]}: $error');
        close();
      }
    }, onError: (Object _) => close(), onDone: () => unawaited(finish(remote)));
  }
}
