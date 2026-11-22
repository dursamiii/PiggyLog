import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_log/auth.dart';
import 'package:piggy_log/main.dart';

class _DashboardRepository implements AuthRepository {
  final List<Map<String, dynamic>> entries = [];
  final List<Map<String, Object?>> savedEntries = [];
  final List<Map<String, Object?>> conversions = [];
  int refreshCount = 0;

  @override
  Future<void> checkConnection(String serverUrl) async {}

  @override
  Future<Map<String, dynamic>> createConversion(
    SavedSession session,
    Map<String, Object?> conversion,
  ) async {
    conversions.add(conversion);
    return {};
  }

  @override
  Future<Map<String, dynamic>> createEntry(
    SavedSession session,
    Map<String, Object?> entry,
  ) async {
    savedEntries.add(entry);
    final created = <String, dynamic>{
      ...entry,
      'id': savedEntries.length,
      'costBasisIdr': entry['amount'],
      'kind': 'saving',
    };
    entries.add(created);
    return created;
  }

  @override
  Future<void> deleteEntry(SavedSession session, int id) async {}

  @override
  Future<List<Map<String, dynamic>>> loadEntries(SavedSession session) async =>
      List.of(entries);

  @override
  Future<Map<String, dynamic>> loadPrices(SavedSession session) async => {
    'prices': {
      'gold': {'idrPerUnit': 2000000},
      'usd': {'idrPerUnit': 16000},
      'sar': {'idrPerUnit': 4000},
    },
  };

  @override
  Future<Map<String, dynamic>?> loadPricesCache(String serverUrl) async => null;

  @override
  Future<SavedSession?> loadSession() async => const SavedSession(
    serverUrl: 'https://piggylog.test',
    token: 'test-token',
  );

  @override
  Future<Map<String, dynamic>> loadSummary(SavedSession session) async => {
    'totalIdr': 12000,
    'profitIdr': 2000,
    'profitPercent': 20,
  };

  @override
  Future<Map<String, dynamic>?> loadSummaryCache(String serverUrl) async =>
      null;

  @override
  Future<String?> loadEntriesCache(String serverUrl) async => null;

  @override
  Future<void> logout(SavedSession session) async {}

  @override
  Future<SavedSession> login(
    String serverUrl,
    String username,
    String password,
  ) async => const SavedSession(
    serverUrl: 'https://piggylog.test',
    token: 'test-token',
  );

  @override
  Future<Map<String, dynamic>> refreshPrices(SavedSession session) async {
    refreshCount += 1;
    return loadPrices(session);
  }

  @override
  Future<void> saveEntriesCache(String serverUrl, String json) async {}

  @override
  Future<void> savePricesCache(
    String serverUrl,
    Map<String, dynamic> prices,
  ) async {}

  @override
  Future<void> saveSummaryCache(
    String serverUrl,
    Map<String, dynamic> summary,
  ) async {}
}

void main() {
  testWidgets('shows server profit and prices and refreshes prices', (
    tester,
  ) async {
    final repository = _DashboardRepository();
    await tester.pumpWidget(PiggyLogApp(authRepository: repository));
    await tester.pumpAndSettle();

    expect(find.text('+Rp 2.000 profit · +20.00% overall'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prices-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Rp 2.000.000'), findsOneWidget);
    expect(find.text('Rp 16.000'), findsOneWidget);
    expect(find.text('Rp 4.000'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('refresh-prices-button')));
    await tester.pumpAndSettle();
    expect(repository.refreshCount, 1);
  });

  testWidgets('gold input remains locked', (tester) async {
    final repository = _DashboardRepository();
    await tester.pumpWidget(PiggyLogApp(authRepository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Gold · locked'), findsOneWidget);
    expect(find.text('Gold savings coming soon'), findsNothing);
    expect(repository.savedEntries, isEmpty);
  });
}
