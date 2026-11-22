import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_log/auth.dart';
import 'package:piggy_log/main.dart';

class _MemoryAuthRepository implements AuthRepository {
  SavedSession? session;
  String? entriesCache;
  bool connected = false;
  final List<Map<String, dynamic>> serverEntries = [];
  final List<Map<String, Object?>> entryRequests = [];
  final List<Map<String, Object?>> conversionRequests = [];
  Map<String, dynamic> summary = {
    'totalIdr': 0,
    'profitIdr': 0,
    'profitPercent': 0,
  };
  Map<String, dynamic> prices = {
    'prices': {
      'gold': {'idrPerUnit': 2000000},
      'usd': {'idrPerUnit': 16000},
      'sar': {'idrPerUnit': 4000},
    },
  };
  Map<String, dynamic>? summaryCache;
  Map<String, dynamic>? pricesCache;
  int refreshCount = 0;

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

  @override
  Future<List<Map<String, dynamic>>> loadEntries(SavedSession session) async =>
      List<Map<String, dynamic>>.of(serverEntries);

  @override
  Future<Map<String, dynamic>> createEntry(
    SavedSession session,
    Map<String, Object?> entry,
  ) async {
    entryRequests.add(entry);
    final created = <String, dynamic>{
      ...entry,
      'id': serverEntries.length + 1,
      'costBasisIdr': entry['amount'],
      'kind': 'saving',
    };
    serverEntries.add(created);
    final amount = (entry['amount'] as num).toDouble();
    final asset = entry['asset'];
    final currentValue = asset == 'idr'
        ? amount
        : amount *
              (((prices['prices'] as Map<String, dynamic>)[asset]
                          as Map<String, dynamic>)['idrPerUnit']
                      as num)
                  .toDouble();
    summary = {'totalIdr': currentValue, 'profitIdr': 0, 'profitPercent': 0};
    return created;
  }

  @override
  Future<void> deleteEntry(SavedSession session, int id) async {
    serverEntries.removeWhere((entry) => entry['id'] == id);
  }

  @override
  Future<Map<String, dynamic>> loadSummary(SavedSession session) async =>
      summary;

  @override
  Future<Map<String, dynamic>?> loadSummaryCache(String serverUrl) async =>
      summaryCache;

  @override
  Future<void> saveSummaryCache(
    String serverUrl,
    Map<String, dynamic> summary,
  ) async {
    summaryCache = summary;
  }

  @override
  Future<Map<String, dynamic>> loadPrices(SavedSession session) async => prices;

  @override
  Future<Map<String, dynamic>> refreshPrices(SavedSession session) async {
    refreshCount += 1;
    return prices;
  }

  @override
  Future<Map<String, dynamic>?> loadPricesCache(String serverUrl) async =>
      pricesCache;

  @override
  Future<void> savePricesCache(
    String serverUrl,
    Map<String, dynamic> prices,
  ) async {
    pricesCache = prices;
  }

  @override
  Future<Map<String, dynamic>> createConversion(
    SavedSession session,
    Map<String, Object?> conversion,
  ) async {
    conversionRequests.add(conversion);
    return {};
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

  testWidgets('logs in, shows dashboard, and logs out from settings', (
    tester,
  ) async {
    final repository = _MemoryAuthRepository();
    await tester.pumpWidget(PiggyLogApp(authRepository: repository));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('server-url-field')),
      'https://piggylog.test',
    );
    await tester.tap(find.byKey(const ValueKey('check-server-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('username-field')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const ValueKey('password-field')),
      'secret',
    );
    await tester.tap(find.byKey(const ValueKey('login-button')));
    await tester.pumpAndSettle();

    expect(find.text('PiggyLog'), findsOneWidget);
    expect(find.text('Rp 0'), findsOneWidget);
    expect(find.text('+Rp 0 profit · +0.00% overall'), findsOneWidget);
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
    expect(find.text('Gold · per gram'), findsOneWidget);
    expect(find.text('USD · 1 USD'), findsOneWidget);
    expect(find.text('SAR · 1 SAR'), findsOneWidget);
    expect(find.text('Rp 2.000.000'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('refresh-prices-button')));
    await tester.pumpAndSettle();
    expect(repository.refreshCount, 1);
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

  testWidgets('saves entries locally and restores them on next app launch', (
    tester,
  ) async {
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
    expect(find.text('Currency'), findsOneWidget);
    expect(find.text('g '), findsOneWidget);
    await tester.tap(find.text('Cash'));
    await tester.pump();
    expect(find.text('Currency'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('amount-field')),
      '1250000',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Saving'), findsOneWidget);
    expect(find.text('Rp 1.250.000'), findsWidgets);
    expect(repository.entriesCache, contains('1250000'));
    expect(repository.entryRequests.single['asset'], 'idr');

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

  testWidgets('records a gold saving and an asset conversion', (tester) async {
    final repository = _MemoryAuthRepository()
      ..session = const SavedSession(
        serverUrl: 'https://piggylog.test',
        token: 'test-token',
      );
    await tester.pumpWidget(PiggyLogApp(authRepository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gold'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('amount-field')), '1,5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repository.entryRequests.single['asset'], 'gold');
    expect(repository.entryRequests.single['amount'], 1.5);

    await tester.tap(find.byKey(const ValueKey('convert-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('convert-amount-field')),
      '10',
    );
    await tester.tap(find.byKey(const ValueKey('submit-conversion-button')));
    await tester.pumpAndSettle();
    expect(repository.conversionRequests.single, {
      'from_asset': 'idr',
      'to_asset': 'usd',
      'amount': 10.0,
    });
  });
}
