"""Opt-in subscription transport check using read-only encrypted local records.

Only the first stored subscription and a stored HY2 node are used. Secrets stay
in memory/private host stdin; response content is neither printed nor persisted.
This verifies transport, not parsing, import, or a production application's UI.
"""
import argparse
from contextlib import closing
from datetime import datetime, timezone
import http.client
import json
import os
from pathlib import Path
import socket
import sqlite3
import ssl
import subprocess
import time
from urllib.parse import urlsplit

from verify_session import Host, ROOT, proxy_snapshot


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', type=Path, default=ROOT / 'build/host/rainlink-host.exe')
    parser.add_argument('--database', type=Path,
                        default=Path(os.environ['APPDATA']) / 'dev.rainlink/rainlink/rainlink.sqlite')
    parser.add_argument('--dart', type=Path,
                        help='Also fetch and parse with the actual Dart subscription adapter')
    parser.add_argument('--output', type=Path,
                        default=ROOT / 'build/subscription-path-evidence.json')
    args = parser.parse_args()
    report = {'at': datetime.now(timezone.utc).isoformat(), 'databaseReadOnly': True,
              'systemProxyRequested': False, 'subscriptionBodyPersisted': False}
    before = proxy_snapshot()
    host = None
    connection = None
    port = None
    try:
        with closing(sqlite3.connect(args.database.resolve().as_uri() + '?mode=ro', uri=True)) as database:
            database.row_factory = sqlite3.Row
            group = database.execute(
                "SELECT id, url_cipher FROM node_groups WHERE kind = 'subscription' ORDER BY id LIMIT 1"
            ).fetchone()
            row = database.execute(
                'SELECT id, name, revision, protocol, server, port, tls, options, credential '
                'FROM nodes WHERE protocol = ? ORDER BY name, id LIMIT 1', ('hysteria2',)
            ).fetchone()
            if group is None or row is None:
                raise ValueError('Required encrypted fixtures unavailable')
            node = {**dict(row), 'tls': bool(row['tls']), 'options': json.loads(row['options'])}
        # serve-test deliberately denies credential reads and normal sessions.
        # A dedicated interactive host uses no system capture for this request.
        host = Host(args.host.resolve())
        source = urlsplit(host.request('reveal', {'id': group['id'], 'cipher': group['url_cipher']})['password'])
        if source.scheme not in ('http', 'https') or not source.hostname or source.username or source.fragment:
            raise ValueError('Invalid stored source')
        live = host.request('connect', {'node': node, 'mode': 'global', 'systemProxy': False})
        port = live['proxyPort']
        report['coreReady'] = live['phase'] == 'connected'
        report['protocol'] = node['protocol']
        path = source.path or '/'
        if source.query:
            path += '?' + source.query
        if source.scheme == 'https':
            connection = http.client.HTTPSConnection('127.0.0.1', port, timeout=20,
                                                      context=ssl.create_default_context())
            connection.set_tunnel(source.hostname, source.port or 443)
        else:
            connection = http.client.HTTPConnection('127.0.0.1', port, timeout=20)
            path = source.geturl()
        connection.request('GET', path, headers={'Host': source.netloc,
                                                 'User-Agent': 'clash.meta RainLink/0.1',
                                                 'Accept': 'application/yaml, application/json, text/plain, */*'})
        response = connection.getresponse()
        received = 0
        limit = 8 * 1024 * 1024
        deadline = time.monotonic() + 20
        while received <= limit:
            if time.monotonic() >= deadline:
                raise TimeoutError('Subscription transport deadline')
            chunk = response.read1(min(64 * 1024, limit + 1 - received))
            if not chunk:
                break
            received += len(chunk)
        report.update(httpStatus=response.status, receivedBytes=received,
                      responseWithinLimit=received <= limit,
                      fetched=response.status == 200 and 0 < received <= limit)
        connection.close()
        connection = None
        if args.dart is not None:
            result = subprocess.run(
                [str(args.dart.resolve()), 'run', 'tool/verify_subscription_path.dart'],
                input=json.dumps({'url': source.geturl(), 'proxyPort': port}) + '\n',
                cwd=ROOT / 'app', stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, encoding='utf-8', timeout=45,
                creationflags=subprocess.CREATE_NO_WINDOW)
            parsed = None
            for line in result.stdout.splitlines():
                try:
                    value = json.loads(line)
                except ValueError:
                    continue
                if isinstance(value, dict) and value.get('productionFetcher') is True:
                    parsed = value
            report['productionFetch'] = parsed
            report['productionFetchPassed'] = result.returncode == 0 and parsed is not None and parsed.get('fetchedAndParsed') is True
    except Exception as error:
        report.update(fetched=False, errorType=type(error).__name__)
    finally:
        if connection is not None:
            connection.close()
        if host is not None:
            try:
                host.request('disconnect')
            except Exception as error:
                report['disconnectErrorType'] = type(error).__name__
            try:
                host.close()
                report['hostCleanedUp'] = True
            except Exception as error:
                report.update(hostCleanedUp=False, cleanupErrorType=type(error).__name__)
            if port is not None:
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=.5):
                        report['listenerClosed'] = False
                except OSError:
                    report['listenerClosed'] = True
        report['exactSystemProxyPreserved'] = proxy_snapshot() == before
    report['passed'] = all(report.get(key) is True for key in (
        'fetched', 'hostCleanedUp', 'listenerClosed', 'exactSystemProxyPreserved'))
    report['passed'] = report['passed'] and 'disconnectErrorType' not in report and (
        args.dart is None or report.get('productionFetchPassed') is True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report), flush=True)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
