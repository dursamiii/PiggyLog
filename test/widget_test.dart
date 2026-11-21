import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_log/auth.dart';
import 'package:piggy_log/main.dart';

class _MemoryAuthRepository implements AuthRepository {
  SavedSession? session;
  String? entriesCache;
  bool connected = false;

  @override
  Future<void> checkConnection(String serverUrl) async {
    connected = serverUrl == 'https://piggylog.test';
    if (!connected) throw const ApiException('Server not found');
  }

  @override
  Future<String?> loadEntriesCache(String serverUrl) async => entriesCache;

  @override
  Future<SavedSession?> loadSession() async => session;

  @override
  Future<SavedSession> login(
    String serverUrl,
    String username,
    String password,
  ) async {
    if (!connected || username != 'alice' || password != 'secret') {
      throw const ApiException('Username atau password salah.');
    }
    return session = SavedSession(serverUrl: serverUrl, token: 'test-token');
  }

  @override
  Future<void> logout(SavedSession session) async {
    this.session = null;
  }

  @override
  Future<void> saveEntriesCache(String serverUrl, String json) async {
    entriesCache = json;
  }
}

void main() {
  testWidgets('checks the server before showing login fields', (tester) async {
    final repository = _MemoryAuthRepository();
    await tester.pumpWidget(PiggyLogApp(authRepository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Check connection'), findsOneWidget);
    expect(find.byKey(const ValueKey('username-field')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('server-url-field')),
      'https://piggylog.test',
    );
    await tester.tap(find.byKey(const ValueKey('check-server-button')));
    await tester.pumpAndSettle();
    expect(find.text('Server terhubung'), findsOneWidget);
    expect(find.byKey(const ValueKey('username-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('password-field')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('edit-server-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('username-field')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('server-url-field')),
      'https://another-server.test',
    );
  });

  testWidgets('logs in, shows dashboard, and logs out from settings', (tester) async {
    final repository = _MemoryAuthRepository();
    await tester.pumpWidget(PiggyLogApp(authRepository: repository));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('server-url-field')),
      'https://piggylog.test',
    );
    await tester.tap(find.byKey(const ValueKey('check-server-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('username-field')), 'alice');
    await tester.enterText(find.byKey(const ValueKey('password-field')), 'secret');
    await tester.tap(find.byKey(const ValueKey('login-button')));
    await tester.pumpAndSettle();

    expect(find.text('PiggyLog'), findsOneWidget);
    expect(find.text('Rp 0'), findsOneWidget);
    expect(find.text('+0% overall'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('No savings yet'), findsOneWidget);
    expect(find.text('1.000'), findsNothing);
    expect(find.byKey(const ValueKey('add-tab')), findsOneWidget);
    expect(find.text('Price updates'), findsNothing);
    expect(find.byKey(const ValueKey('balance-island')), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom-navigation')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prices-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Price updates'), findsOneWidget);
    expect(find.text('Gold'), findsOneWidget);
    expect(find.text('USD'), findsOneWidget);
    expect(find.text('SAR'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-tab')));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('https://piggylog.test'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('logout-button')));
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);
    await tester.tap(find.text('Log out').last);
    await tester.pumpAndSettle();
    expect(repository.session, isNull);
    expect(find.byKey(const ValueKey('server-url-field')), findsOneWidget);
  });

  testWidgets('saves entries locally and restores them on next app launch', (tester) async {
    final repository = _MemoryAuthRepository()
      ..session = const SavedSession(
        serverUrl: 'https://piggylog.test',
        token: 'test-token',
      );
    await tester.pumpWidget(PiggyLogApp(authRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Gold'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Source (optional)'), findsOneWidget);
    expect(find.byKey(const ValueKey('balance-island')), findsOneWidget);
    await tester.tap(find.text('Gold'));
    await tester.pump();
    expect(find.text('Gold savings coming soon'), findsOneWidget);
    expect(find.text('Price updates will be connected later.'), findsOneWidget);
    await tester.tap(find.text('Cash'));
    await tester.pump();
    expect(find.text('Currency'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('amount-field')), '1250000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Saving'), findsOneWidget);
    expect(find.text('Rp 1.250.000'), findsWidgets);
    expect(repository.entriesCache, contains('1250000'));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(PiggyLogApp(authRepository: repository));
    await tester.pumpAndSettle();
    expect(find.text('Saving'), findsOneWidget);
    expect(find.text('Rp 1.250.000'), findsWidgets);

    await tester.longPress(find.text('Saving'));
    await tester.pumpAndSettle();
    expect(find.text('Delete saving?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Saving'), findsOneWidget);
  });
}
