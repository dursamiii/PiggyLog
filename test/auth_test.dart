import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:piggy_log/auth.dart';

void main() {
  test('checks the PiggyLog health endpoint under the supplied base path', () async {
    http.Request? received;
    final repository = ServerAuthRepository(
      client: MockClient((request) async {
        received = request;
        return http.Response('{"ok":true}', 200);
      }),
    );

    await repository.checkConnection('https://piggylog.example/api/');

    expect(received?.method, 'GET');
    expect(
      received?.url,
      Uri.parse('https://piggylog.example/api/health'),
    );
  });

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
}
