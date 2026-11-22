import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_log/auth.dart';
import 'package:piggy_log/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ThemeHistoryRepository implements AuthRepository {
  _ThemeHistoryRepository({List<Map<String, dynamic>>? entries})
    : entries = entries ?? [];

  final List<Map<String, dynamic>> entries;

  @override
  Future<void> checkConnection(String serverUrl) async {}

  @override
  Future<Map<String, dynamic>> createConversion(
    SavedSession session,
    Map<String, Object?> conversion,
  ) async => {};

  @override
  Future<Map<String, dynamic>> createEntry(
    SavedSession session,
    Map<String, Object?> entry,
  ) async => {...entry, 'id': entries.length + 1, 'costBasisIdr': 1};

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
    'totalIdr': 100000,
    'profitIdr': 5000,
    'profitPercent': 5,
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
  Future<Map<String, dynamic>> refreshPrices(SavedSession session) async =>
      loadPrices(session);

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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('dark theme can be selected in settings and is remembered', (
    tester,
  ) async {
    final repository = _ThemeHistoryRepository();
    await tester.pumpWidget(PiggyLogApp(authRepository: repository));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byKey(const ValueKey('balance-island'))))
          .brightness,
      Brightness.light,
    );

    await tester.tap(find.byKey(const ValueKey('settings-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dark-theme-switch')));
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.byKey(const ValueKey('dark-theme-switch'))))
          .brightness,
      Brightness.dark,
    );
    expect(
      (await SharedPreferences.getInstance()).getString('piggylog.theme_mode'),
      'dark',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(PiggyLogApp(authRepository: repository));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byKey(const ValueKey('balance-island'))))
          .brightness,
      Brightness.dark,
    );
  });

  testWidgets('history groups months and uses asset-specific marks', (
    tester,
  ) async {
    final repository = _ThemeHistoryRepository(
      entries: [
        _entry(1, 'gold', DateTime(2026, 5, 8), 1),
        _entry(2, 'sar', DateTime(2026, 4, 17), 50),
        _entry(3, 'usd', DateTime(2026, 4, 12), 10),
        _entry(4, 'idr', DateTime(2026, 4, 2), 50000),
      ],
    );
    await tester.pumpWidget(PiggyLogApp(authRepository: repository));
    await tester.pumpAndSettle();

    expect(find.text('May 2026'), findsOneWidget);
    expect(find.text('April 2026'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('ر.س'), findsOneWidget);
    expect(find.text('Rp'), findsOneWidget);
    expect(find.byIcon(Icons.attach_money), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_GoldBarPainter',
      ),
      findsOneWidget,
    );
  });
}

Map<String, dynamic> _entry(int id, String asset, DateTime date, num amount) =>
    {
      'id': id,
      'asset': asset,
      'amount': amount,
      'source': 'Test saving',
      'date': date.toIso8601String(),
      'costBasisIdr': 1000,
      'kind': 'saving',
    };
