import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:piggy_log/auth.dart';

void main() {
  test(
    'checks the PiggyLog health endpoint under the supplied base path',
    () async {
      http.Request? received;
      final repository = ServerAuthRepository(
        client: MockClient((request) async {
          received = request;
          return http.Response('{"ok":true}', 200);
        }),
      );

      await repository.checkConnection('https://piggylog.example/api/');

      expect(received?.method, 'GET');
      expect(received?.url, Uri.parse('https://piggylog.example/api/health'));
    },
  );

  test('rejects a reachable endpoint that is not the PiggyLog API', () async {
    final repository = ServerAuthRepository(
      client: MockClient((_) async => http.Response('{"status":"ok"}', 200)),
    );

    await expectLater(
      repository.checkConnection('https://example.test'),
      throwsA(isA<ApiException>()),
    );
  });

  test('requires an explicit HTTP scheme in the server URL', () async {
    final repository = ServerAuthRepository(
      client: MockClient((_) async => http.Response('{"ok":true}', 200)),
    );

    await expectLater(
      repository.checkConnection('piggylog.example'),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'uses authenticated price, summary, entry, and conversion endpoints',
    () async {
      final requests = <http.Request>[];
      final repository = ServerAuthRepository(
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/entries') &&
              request.method == 'GET') {
            return http.Response('[]', 200);
          }
          if (request.url.path.endsWith('/entries')) {
            return http.Response('{"id":1}', 201);
          }
          return http.Response('{"prices":{}}', 200);
        }),
      );
      const session = SavedSession(
        serverUrl: 'https://piggylog.example',
        token: 'test-token',
      );

      await repository.loadPrices(session);
      await repository.refreshPrices(session);
      await repository.loadSummary(session);
      await repository.loadEntries(session);
      await repository.createEntry(session, {
        'asset': 'usd',
        'amount': 10,
        'source': 'Cash',
      });
      await repository.createConversion(session, {
        'from_asset': 'usd',
        'to_asset': 'idr',
        'amount': 1,
      });

      expect(requests.map((request) => request.url.path), [
        '/api/v1/prices',
        '/api/v1/prices/refresh',
        '/api/v1/summary',
        '/api/v1/entries',
        '/api/v1/entries',
        '/api/v1/conversions',
      ]);
      for (final request in requests) {
        expect(request.headers['authorization'], 'Bearer test-token');
      }
      expect(requests[1].method, 'POST');
      expect(jsonDecode(requests[4].body), {
        'asset': 'usd',
        'amount': 10,
        'source': 'Cash',
      });
      expect(requests[5].method, 'POST');
      expect(jsonDecode(requests[5].body), {
        'from_asset': 'usd',
        'to_asset': 'idr',
        'amount': 1,
      });
    },
  );
}
